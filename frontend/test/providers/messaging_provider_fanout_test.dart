import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/services/device_list/device_list_cache.dart';
import 'package:fireplace/services/device_list/device_list_canonical.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Send fan-out contracts (multi-device spec §5.2 + §12 amendments (v)/(vi)/(x)).
///
/// The Signal handshake is faked — a per-address deterministic ciphertext is all
/// these contracts need — but the fan-out decision, the envelope shape, the
/// version stamps and the stale-refusal repair are the real provider code.
class _FanOutEncryption extends EncryptionProvider {
  _FanOutEncryption();

  /// Lists this fake serves for `getDeviceList`-style resolution, by userId.
  /// Absent = the server would answer `authorization: null` (not enrolled).
  final Map<int, VerifiedDeviceList> served = {};

  /// Lists already cached, i.e. what a send may fan out to with no round trip.
  final Map<int, VerifiedDeviceList> _cache = {};

  final List<(int, int)> encryptCalls = [];
  int _ownDeviceId = 1;

  @override
  bool get isE2EReady => true;

  @override
  bool get hadIdentityReset => false;

  @override
  int get ownDeviceId => _ownDeviceId;

  @override
  void setOwnDeviceId(int deviceId) => _ownDeviceId = deviceId;

  @override
  VerifiedDeviceList? cachedDeviceList(int userId) => _cache[userId];

  @override
  Future<VerifiedDeviceList> getVerifiedDeviceList(
    int userId, {
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final resolved = served[userId] ?? const VerifiedDeviceList.notEnrolled();
    _cache[userId] = resolved;
    return resolved;
  }

  @override
  Future<VerifiedDeviceList> adoptDeliveredDeviceList(
    int userId,
    Map<String, dynamic>? authorization,
  ) async {
    // The chain check itself is covered by the C2 cache tests; here the point
    // is that a refusal's payload lands in the cache so the resend can fan out.
    final adopted = served[userId] ?? const VerifiedDeviceList.notEnrolled();
    _cache[userId] = adopted;
    return adopted;
  }

  @override
  Future<void> ensureSession(int recipientId, {int deviceId = 1}) async {}

  @override
  Future<void> deleteSessionWithPeer(int peerUserId) async {}

  @override
  Future<String> encrypt(
    int recipientId,
    String plaintext, {
    int deviceId = 1,
  }) async {
    encryptCalls.add((recipientId, deviceId));
    return '2:ct-for-$recipientId-$deviceId';
  }

  @override
  Future<void> savePendingSendRecord(
    String key,
    Map<String, dynamic> data,
  ) async {}
}

VerifiedDeviceList _enrolled(int version, List<int> deviceIds) =>
    VerifiedDeviceList.enrolled(
      version: version,
      devices: [
        for (final id in deviceIds)
          DeviceListEntry(deviceId: id, platform: 'test', addedAtMs: 0),
      ],
    );

Map<String, dynamic> _convJson() => {
  'id': 10,
  'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
  'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
  'createdAt': '2026-01-01T00:00:00.000Z',
  'disappearingTimer': 60,
  'unreadCount': 0,
  'lastMessage': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessagingProvider — send fan-out', () {
    late MessagingProvider provider;
    late ConversationsProvider conversations;
    late _FanOutEncryption encryption;
    late List<Map<String, dynamic>> emitted;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});

      provider = MessagingProvider();
      conversations = ConversationsProvider();
      encryption = _FanOutEncryption();
      emitted = <Map<String, dynamic>>[];

      conversations.setCurrentUserId(1);
      conversations.onConversationsList([_convJson()]);
      conversations.openConversation(10);

      provider.setConversationsProvider(conversations);
      provider.setEncryptionProvider(encryption);
      provider.setCurrentUserId(1);
      provider.setToken('tok');
      provider.setIncomingMessageSoundEnabledForTest(false);
      provider.onConnect(false);
      provider.setActiveConversationIdForTest(10);
      provider.setEmitCallback((event, data) {
        emitted.add({'event': event, 'data': data});
      });
    });

    Future<void> pump([int turns = 30]) async {
      for (var i = 0; i < turns; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    List<Map<String, dynamic>> sends() => [
      for (final e in emitted)
        if (e['event'] == 'sendMessage') e['data'] as Map<String, dynamic>,
    ];

    Future<Map<String, dynamic>> sendAndCapture(String text) async {
      provider.sendMessage(text);
      await pump();
      return sends().last;
    }

    test(
      'no cached list: sends the LEGACY single-ciphertext shape, no round trip',
      () async {
        final send = await sendAndCapture('hello');

        // Paying a device-list fetch per send to prove a single-device account
        // is single-device would slow the common path for nothing; the server
        // refuses a legacy send the moment either party is enrolled.
        expect(send.containsKey('envelopes'), isFalse);
        expect(send['encryptedContent'], '2:ct-for-2-1');
        expect(send.containsKey('recipientListVersion'), isFalse);
        expect(send.containsKey('senderListVersion'), isFalse);
        // The token is minted regardless: it is the idempotency key.
        expect(send['sendToken'], isA<String>());
        expect(encryption.encryptCalls, [(2, 1)]);
      },
    );

    test('cached recipient list: one DISTINCT ciphertext per device', () async {
      encryption.served[2] = _enrolled(4, [1, 2]);
      await encryption.getVerifiedDeviceList(2);

      final send = await sendAndCapture('hello');

      final envelopes = (send['envelopes'] as List)
          .cast<Map<String, dynamic>>();
      expect(envelopes, hasLength(2));
      expect(
        envelopes.map((e) => (e['userId'], e['deviceId'])),
        containsAll([(2, 1), (2, 2)]),
      );
      // Reusing one ciphertext across devices would consume the same message
      // key twice and brick every device but the first.
      expect(
        envelopes.map((e) => e['ciphertext']).toSet(),
        hasLength(envelopes.length),
      );
      expect(send['recipientListVersion'], 4);
      expect(send.containsKey('encryptedContent'), isFalse);
    });

    test(
      'own other devices get a self-sync envelope; the origin device never does',
      () async {
        encryption.served[2] = _enrolled(4, [1]);
        encryption.served[1] = _enrolled(7, [1, 2, 3]);
        await encryption.getVerifiedDeviceList(2);
        await encryption.getVerifiedDeviceList(1);
        encryption.setOwnDeviceId(2);

        final send = await sendAndCapture('hello');

        final addresses = (send['envelopes'] as List)
            .cast<Map<String, dynamic>>()
            .map((e) => (e['userId'], e['deviceId']))
            .toList();
        expect(addresses, containsAll([(2, 1), (1, 1), (1, 3)]));
        // Device 2 is US: it holds the plaintext already, and the server
        // refuses that envelope as self_envelope_for_origin_device.
        expect(addresses, isNot(contains((1, 2))));
        expect(send['senderListVersion'], 7);
      },
    );

    test('revoked devices are never addressed', () async {
      encryption.served[2] = VerifiedDeviceList.enrolled(
        version: 9,
        devices: const [
          DeviceListEntry(deviceId: 1, platform: 'test', addedAtMs: 0),
          DeviceListEntry(
            deviceId: 2,
            platform: 'test',
            addedAtMs: 0,
            revokedAtMs: 1,
          ),
        ],
      );
      await encryption.getVerifiedDeviceList(2);

      final send = await sendAndCapture('hello');

      final envelopes = (send['envelopes'] as List)
          .cast<Map<String, dynamic>>();
      expect(envelopes, hasLength(1));
      expect(envelopes.single['deviceId'], 1);
    });

    test(
      'a retry of the same send reuses its sendToken (idempotency, §5.4)',
      () async {
        final first = await sendAndCapture('hello');
        final tempId = first['tempId'] as String;
        final token = first['sendToken'] as String;

        provider.markSendingMessagesFailed('dropped');
        await provider.retryFailedMessage(tempId);
        await pump();

        final resent = sends().last;
        expect(resent['tempId'], tempId);
        // A retry carrying the same token re-acks the row the server already
        // committed instead of duplicating the message.
        expect(resent['sendToken'], token);
      },
    );

    group('deviceListStale repair (§12 (vi)/(x))', () {
      /// The refusal payload the server emits, carrying each stale party's
      /// full signed list.
      Map<String, dynamic> refusal(String tempId, List<int> staleUserIds) => {
        'success': false,
        'error': 'device_list_stale',
        'tempId': tempId,
        'lists': [
          for (final userId in staleUserIds)
            {
              'userId': userId,
              'version': 4,
              'listCanonical': 'canon-$userId',
              'listSignature': 'lsig-$userId',
              'enrollment': {
                'dakPub': 'dak-$userId',
                'enrollmentSig': 'esig-$userId',
                'enrollmentCreatedAt': 1700000000000,
              },
            },
        ],
      };

      test('adopts the delivered list and resends as a fan-out', () async {
        final first = await sendAndCapture('hello');
        expect(first.containsKey('envelopes'), isFalse);
        final tempId = first['tempId'] as String;

        // The recipient turns out to be enrolled with two devices.
        encryption.served[2] = _enrolled(4, [1, 2]);
        await provider.onDeviceListStale(refusal(tempId, [2]));
        await pump();

        final resent = sends().last;
        expect(resent['tempId'], tempId);
        final envelopes = (resent['envelopes'] as List)
            .cast<Map<String, dynamic>>();
        expect(envelopes, hasLength(2));
        expect(resent['recipientListVersion'], 4);
      });

      test(
        'resolves a party MISSING from lists[] so the resend can fan out',
        () async {
          // Enrolled sender, non-enrolled recipient: the refusal names only the
          // sender, so without explicitly resolving the recipient the resend
          // would repeat the legacy shape and loop until the cap.
          final first = await sendAndCapture('hello');
          final tempId = first['tempId'] as String;
          encryption.served[1] = _enrolled(7, [1, 2]);

          await provider.onDeviceListStale(refusal(tempId, [1]));
          await pump();

          final resent = sends().last;
          final addresses = (resent['envelopes'] as List)
              .cast<Map<String, dynamic>>()
              .map((e) => (e['userId'], e['deviceId']))
              .toList();
          // The recipient resolved as not-enrolled => device 1, and is
          // addressed. A fan-out that named only own devices would make the
          // message permanently invisible to its actual recipient.
          expect(addresses, contains((2, 1)));
          expect(addresses, contains((1, 2)));
        },
      );

      test('gives up after 3 attempts with a surfaced failure', () async {
        final first = await sendAndCapture('hello');
        final tempId = first['tempId'] as String;

        for (var i = 0; i < 4; i++) {
          await provider.onDeviceListStale(refusal(tempId, [2]));
          await pump();
        }

        final row = provider.messages.firstWhere((m) => m.tempId == tempId);
        expect(row.deliveryStatus, MessageDeliveryStatus.failed);
      });
    });
  });
}
