import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `envelopeStatus` handling (multi-device spec §5.3 + §12 amendment (viii)).
///
/// A row the server marked has NO ciphertext for this device. The contracts that
/// matter are all about what must NOT happen to it: it must not be decrypted
/// (which would land in the decryption-failure policy), it must not overwrite a
/// plaintext copy this device already holds, and it must never be a destruction
/// trigger (I8, falsification 13).
class _NoopEncryption extends EncryptionProvider {
  int decryptCalls = 0;

  @override
  bool get isE2EReady => true;

  @override
  bool get hadIdentityReset => false;

  @override
  Future<void> ensureSession(int recipientId, {int deviceId = 1}) async {}

  @override
  Future<String> decrypt(
    int senderId,
    String ciphertext, {
    int? messageId,
    int deviceId = 1,
  }) async {
    decryptCalls++;
    return '{"content":"should never be reached"}';
  }
}

Map<String, dynamic> _convJson() => {
  'id': 10,
  'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
  'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
  'createdAt': '2026-01-01T00:00:00.000Z',
  'disappearingTimer': null,
  'unreadCount': 0,
  'lastMessage': null,
};

Map<String, dynamic> _row({
  required int id,
  String? envelopeStatus,
  String? encryptedContent,
  int senderId = 2,
}) => {
  'id': id,
  'senderId': senderId,
  'senderUsername': senderId == 1 ? 'alice' : 'bob',
  'content': '[encrypted]',
  'encryptedContent': ?encryptedContent,
  'envelopeStatus': ?envelopeStatus,
  'conversationId': 10,
  'deliveryStatus': 'DELIVERED',
  'messageType': 'TEXT',
  'createdAt': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('envelopeStatus', () {
    late MessagingProvider provider;
    late ConversationsProvider conversations;
    late _NoopEncryption encryption;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});

      provider = MessagingProvider();
      conversations = ConversationsProvider();
      encryption = _NoopEncryption();

      conversations.setCurrentUserId(1);
      conversations.onConversationsList([_convJson()]);
      conversations.openConversation(10);

      provider.setConversationsProvider(conversations);
      provider.setEncryptionProvider(encryption);
      provider.setCurrentUserId(1);
      provider.setIncomingMessageSoundEnabledForTest(false);
      provider.onConnect(false);
      provider.setActiveConversationIdForTest(10);
      provider.setEmitCallback((event, data) {});
    });

    Future<void> pump([int turns = 30]) async {
      for (var i = 0; i < turns; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('the model carries both marker values off the wire', () {
      expect(
        MessageModel.fromJson(
          _row(id: 1, envelopeStatus: 'none_for_device'),
        ).envelopeStatus,
        'none_for_device',
      );
      expect(
        MessageModel.fromJson(
          _row(id: 2, envelopeStatus: 'own_origin', senderId: 1),
        ).envelopeStatus,
        'own_origin',
      );
      // Absent on an older server, and on any row that DID get a ciphertext.
      expect(
        MessageModel.fromJson(
          _row(id: 3, encryptedContent: '2:ct'),
        ).envelopeStatus,
        isNull,
      );
    });

    test('a none_for_device row is never decrypted and renders the honest '
        'placeholder', () async {
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_row(id: 101, envelopeStatus: 'none_for_device')],
      });
      await pump();

      final row = provider.messages.firstWhere((m) => m.id == 101);
      // NOT '[Decryption failed]': nothing failed, the row simply predates this
      // device's link.
      expect(row.content, kNotLinkedYetMessageLabel);
      expect(encryption.decryptCalls, 0);
    });

    test('a marker row is not a destruction trigger', () async {
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_row(id: 102, envelopeStatus: 'none_for_device')],
      });
      await pump();

      // The row survives as a placeholder — I8: an honest marker never purges,
      // retires, or removes anything (falsification 13).
      expect(provider.messages.any((m) => m.id == 102), isTrue);
      final row = provider.messages.firstWhere((m) => m.id == 102);
      expect(row.content, isNot(kRetiredMessageLabel));
    });

    test('the marker can never overwrite plaintext already held', () {
      // saveDecryptedContent refuses a placeholder over real content, and the
      // marker must be part of that set or a later marked payload would erase a
      // message this device legitimately decrypted.
      expect(
        EncryptionService.placeholderContents,
        contains(kNotLinkedYetMessageLabel),
      );
    });

    test('copyWith preserves the per-device fields', () {
      final row = MessageModel.fromJson(
        _row(id: 104, envelopeStatus: 'own_origin', senderId: 1),
      ).copyWith(deliveryStatus: MessageDeliveryStatus.read);

      // Losing these on a merge would resurrect a decrypt attempt on a row with
      // no ciphertext for this device, or drop the origin device's reconcile key.
      expect(row.envelopeStatus, 'own_origin');
    });
  });

  group('(lxvi) clause 2 — local plaintext outranks the none_for_device marker',
      () {
    // A re-linked install is a NEW device id (amendment (a): ids are never
    // reused), so the history read answers `none_for_device` for every row
    // that predates it — including rows THIS install already decrypted and
    // sealed under its previous id. Live QA 2026-09-02: those rows rendered
    // "sent before this device was linked" while the plaintext sat on disk.
    //
    // Falsification contract: removing `kNotLinkedYetMessageLabel` from
    // `_hasUsableDecryptedContent`'s placeholder set turns the first test RED
    // (the hydration pass counts the sentinel as usable and never consults
    // storage); the second is the control that a genuinely pre-link row is
    // unchanged.
    late MessagingProvider provider;
    late ConversationsProvider conversations;
    late EncryptionProvider encryption;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});

      encryption = EncryptionProvider();
      encryption.setEmitCallback((event, data) {
        if (event == 'checkOwnKeyBundle') {
          encryption.onOwnKeyBundleStatus({'exists': false});
        }
      });
      encryption.setOwnDeviceId(3);
      await encryption.initializeE2E(1);
      await pumpEventQueue(times: 200);

      provider = MessagingProvider();
      conversations = ConversationsProvider();
      conversations.setCurrentUserId(1);
      conversations.onConversationsList([_convJson()]);
      conversations.openConversation(10);
      provider.setConversationsProvider(conversations);
      provider.setEncryptionProvider(encryption);
      provider.setCurrentUserId(1);
      provider.setIncomingMessageSoundEnabledForTest(false);
      provider.onConnect(false);
      provider.setActiveConversationIdForTest(10);
      provider.setEmitCallback((event, data) {});
    });

    test('a marked row this install already decrypted renders its sealed '
        'plaintext, not the placeholder', () async {
      // Sealed under the previous device id, exactly as the decrypt pass
      // persists a successful decrypt.
      await encryption.saveDecryptedContent(201, {
        'content': 'msg1 decrypted as device 2',
        'messageType': 'TEXT',
      }, conversationId: 10);
      expect(
        (await encryption.getDecryptedContent(201))?['content'],
        'msg1 decrypted as device 2',
      );

      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_row(id: 201, envelopeStatus: 'none_for_device')],
      });
      await pumpEventQueue(times: 200);

      final row = provider.messages.firstWhere((m) => m.id == 201);
      expect(row.content, 'msg1 decrypted as device 2');
      expect(row.envelopeStatus, 'none_for_device');
    });

    test('a marked row with nothing local keeps the honest placeholder',
        () async {
      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [_row(id: 202, envelopeStatus: 'none_for_device')],
      });
      await pumpEventQueue(times: 200);

      final row = provider.messages.firstWhere((m) => m.id == 202);
      expect(row.content, kNotLinkedYetMessageLabel);
    });
  });
}
