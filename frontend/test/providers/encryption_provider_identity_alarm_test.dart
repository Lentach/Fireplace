// U4 / amendment (xlvi) clause 2: the alarm must REACH THE USER.
//
// The store raising `onIdentityChanged` was already proven. What was NOT
// proven is that the raise survives the trip to the widget tree, and the two
// existing tests each let the harness play a production part:
//
//   * `test/services/encryption_account_anchor_test.dart` attaches its own
//     callback to a bare `SecureIdentityKeyStore` (`peerStore.onIdentityChanged
//     = ...`), so the SERVICE's own wiring is never exercised.
//   * `test/widgets/identity_banners_test.dart` overrides
//     `peersWithChangedIdentity` on a fake provider, so the SERVICE never sets
//     the state the widget reads.
//
// Between them the production wire — store -> service callback -> provider
// state -> notifyListeners -> `context.select` rebuild — was never run end to
// end. This file runs it: a real EncryptionService owned by a real
// EncryptionProvider, driven through the real `buildSession` path.
//
// The `notifyListeners` assertion is the point. Without a notify the state is
// still correct and the row still cannot appear until some unrelated rebuild
// happens to run — which is precisely the "correct and unwired guard" shape
// this programme keeps producing (T6 shipped a revoke that never armed its
// DAK, and the unit suite was green because the test pre-armed the engine).

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownUserId = 7;
  const peerId = 42;

  // The peer's post-§6.2 device id. Ids are never reused ((a)), so a recovered
  // account is reached at a fresh id and device 1 is gone for good.
  const peerNewDeviceId = 5;

  late EncryptionProvider provider;
  late EncryptionService peer;
  late EncryptionService peerAfterReset;

  /// The FLAT bundle map `buildSession` expects, exactly as the server serves
  /// `fetchPreKeyBundle`.
  Map<String, dynamic> flatBundleFrom(EncryptionService source) {
    final upload = source.getKeysForUpload();
    expect(upload, isNotNull);
    final keyBundle = (upload!['keyBundle'] as Map).cast<String, dynamic>();
    final otps = (upload['oneTimePreKeys'] as List).cast<Map<String, dynamic>>();
    expect(otps, isNotEmpty);
    return {
      ...keyBundle,
      'oneTimePreKeyId': otps.first['keyId'],
      'oneTimePreKeyPublic': otps.first['publicKey'],
    };
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    provider = EncryptionProvider();
    provider.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        provider.onOwnKeyBundleStatus({'exists': false});
      }
    });
    await provider.initializeE2E(ownUserId);
    expect(
      provider.isE2EReady,
      isTrue,
      reason: 'the alarm cannot be tested through a provider that never armed',
    );

    // The peer's real engine, pre-reset.
    peer = EncryptionService();
    await peer.initialize(peerId, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));

    // The SAME account after a §6.2 identity reset: a genuinely different
    // identity key, served under the same user id at a fresh device id. A
    // separate engine id keeps its storage prefix distinct; only its bundle is
    // ever used, and always under `peerId`.
    peerAfterReset = EncryptionService();
    await peerAfterReset.initialize(
      9001,
      checkServerIdentity: () async => const ServerIdentityGuard(exists: false),
    );
  });

  /// First contact, at the device id a non-enrolled account has by
  /// construction. This is what pins the account anchor.
  Future<void> establishAccountPin() async {
    await provider.encryptionService.buildSession(
      peerId,
      flatBundleFrom(peer),
      expectedIdentityBase64: null,
    );
    expect(
      provider.peersWithChangedIdentity,
      isEmpty,
      reason: 'TOFU first contact is silent by design',
    );
  }

  test(
    'a peer reset arriving on a NEW device id notifies the widget tree',
    () async {
      await establishAccountPin();

      var notifications = 0;
      provider.addListener(() => notifications++);

      // The (xlvi) clause-2 shape: an address we have never seen, carrying a
      // key that differs from the accepted ACCOUNT key. Per-address TOFU used
      // to read this as first contact and say nothing.
      await provider.encryptionService.buildSession(
        peerId,
        flatBundleFrom(peerAfterReset),
        deviceId: peerNewDeviceId,
        expectedIdentityBase64: null,
      );

      expect(
        provider.peersWithChangedIdentity,
        contains(peerId),
        reason:
            'the event §6.2 promises to announce must land in provider state',
      );
      expect(
        notifications,
        greaterThan(0),
        reason:
            'without a notify the row cannot appear until an unrelated rebuild '
            'happens to run — the alarm would be decorative',
      );
    },
  );

  test('an ordinary new device on the same account stays quiet', () async {
    await establishAccountPin();

    var notifications = 0;
    provider.addListener(() => notifications++);

    // A legitimate second device: same account identity key, new address.
    // Alarming here would train people to dismiss the one surface that
    // detects a real takeover.
    await provider.encryptionService.buildSession(
      peerId,
      flatBundleFrom(peer),
      deviceId: peerNewDeviceId,
      expectedIdentityBase64: null,
    );

    expect(provider.peersWithChangedIdentity, isEmpty);
    expect(
      notifications,
      0,
      reason: 'an ordinary link must not raise the takeover surface',
    );
  });

  test(
    'acknowledging clears the alarm and notifies, so the row can disappear',
    () async {
      await establishAccountPin();
      await provider.encryptionService.buildSession(
        peerId,
        flatBundleFrom(peerAfterReset),
        deviceId: peerNewDeviceId,
        expectedIdentityBase64: null,
      );
      expect(provider.peersWithChangedIdentity, contains(peerId));

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.acknowledgePeerIdentity(peerId);

      expect(provider.peersWithChangedIdentity, isEmpty);
      expect(
        notifications,
        greaterThan(0),
        reason:
            'the row must clear on acknowledgement, or the user cannot tell '
            'the warning was accepted',
      );
      // The acknowledgement is also what promotes the held candidate to the
      // anchor; without that the peer stays unverifiable with no way to say so.
      expect(
        await provider.encryptionService.peerTofuIdentityBase64(peerId),
        flatBundleFrom(peerAfterReset)['identityPublicKey'],
        reason: 'acknowledgement must advance the anchor to the accepted key',
      );
    },
  );
}
