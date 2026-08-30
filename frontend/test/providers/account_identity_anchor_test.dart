// F4 / KA-02 (spec §12 amendment (lvi)): the (xxxix) expected-identity gate was
// VACUOUS in the two states that are the default rather than the edge.
//
// `_accountIdentityAnchor` resolved the anchor by scanning per-device rows of
// the CACHED verified device list, excluding the device being built, and
// `buildSession` no-ops when the expected identity is null. So the anchor came
// back null — and the §3 account-wide identity binding went unenforced — for:
//
//   1. ANY COLD CACHE. The verified-list cache is memory-only, so every first
//      send after launch resolved nothing.
//   2. ANY SINGLE-LIVE-DEVICE PEER. `notEnrolled()` synthesises device 1 alone,
//      so the only candidate IS the device being built, and it is skipped. That
//      is every non-enrolled account — i.e. most users.
//
// These tests drive the REAL provider `ensureSession` against a server that
// serves a FOREIGN identity key for a peer whose real key this device already
// pinned. That is exactly the capability §2 says a server alone does not have.
//
// WHAT EACH TEST IS FOR:
//   1. cold cache: the substitution is REFUSED, not silently trusted
//   2. cold cache: the refusal is VISIBLE ((lv)), or it is just a dead chat
//   3. single-live-device peer: same refusal on the most common account shape
//   4. POSITIVE CONTROL: the peer's OWN key still builds on a cold cache — the
//      fix must not block ordinary messaging, which is the whole risk of (lvi)
//   5. POSITIVE CONTROL: genuine first contact with an ACCOUNT stays TOFU
//
// Everything here is a real production object except the socket transport.

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownUserId = 7;
  const peerId = 42;

  late EncryptionProvider enc;
  late EncryptionService peer;
  late EncryptionService mallory;

  /// Which identity the stubbed server serves for the peer's bundle.
  late EncryptionService served;

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

    peer = EncryptionService();
    await peer.initialize(peerId, checkServerBundleExists: () async => false);
    mallory = EncryptionService();
    await mallory.initialize(99, checkServerBundleExists: () async => false);
    served = peer;

    enc = EncryptionProvider();
    enc.setEmitCallback((event, data) {
      if (event == 'checkOwnKeyBundle') {
        enc.onOwnKeyBundleStatus({'exists': false});
      }
      if (event == 'fetchPreKeyBundle') {
        enc.onPreKeyBundleResponse({
          'userId': peerId,
          'deviceId': (data as Map)['deviceId'] ?? 1,
          'bundle': flatBundleFrom(served),
        });
      }
      // No 'getDeviceList' handler on purpose: the verified-list cache stays
      // EMPTY, which is the cold-cache state every launch begins in.
    });
    await enc.initializeE2E(ownUserId);
  });

  /// First contact the honest way: pins the peer's real key as the ACCOUNT
  /// anchor, exactly as an ordinary conversation would.
  Future<void> pinPeerHonestly() async {
    await enc.encryptionService.buildSession(
      peerId,
      flatBundleFrom(peer),
      expectedIdentityBase64: null,
    );
    expect(enc.peersWithChangedIdentity, isEmpty);
    expect(
      await enc.encryptionService.peerTofuIdentityBase64(peerId),
      isNotNull,
      reason: 'the account anchor is the state the whole fix depends on',
    );
  }

  group('(lvi) the account anchor backs the (xxxix) gate', () {
    test('COLD CACHE: a substituted identity is REFUSED', () async {
      await pinPeerHonestly();
      expect(
        enc.cachedDeviceList(peerId),
        isNull,
        reason: 'this test is only meaningful while the cache is cold',
      );

      // The server now answers the peer's bundle fetch with Mallory's key, on
      // a device id the peer's list could legitimately name.
      served = mallory;

      await expectLater(
        enc.ensureSession(peerId, deviceId: 2),
        throwsA(isA<AccountIdentityMismatch>()),
      );

      // Fail CLOSED: nothing trusted, so a retry cannot find the attacker's
      // key already in place.
      expect(await enc.encryptionService.peerIdentityAt(peerId, 2), isNull);
    });

    test('COLD CACHE: the refusal is VISIBLE, not a dead chat', () async {
      await pinPeerHonestly();
      served = mallory;

      await expectLater(
        enc.ensureSession(peerId, deviceId: 2),
        throwsA(isA<AccountIdentityMismatch>()),
      );

      // (lv) is a hard prerequisite of (lvi): without the banner this ruling
      // would trade a MITM window for a permanent unexplained lockout.
      expect(enc.peersWithChangedIdentity, contains(peerId));
      final verification = await enc.encryptionService
          .peerIdentityVerification(peerId);
      expect(
        verification.offeredIdentityBase64,
        flatBundleFrom(mallory)['identityPublicKey'],
        reason: 'the ceremony must be able to show the key that was refused',
      );
    });

    test('SINGLE LIVE DEVICE: the substitution is REFUSED there too', () async {
      await pinPeerHonestly();

      // The most common account shape: the peer has never enrolled, so their
      // synthesised list names device 1 alone — the very device being built.
      // Before (lvi) the per-device scan skipped it and resolved nothing.
      await expectLater(
        enc.ensureSession(peerId),
        completes,
        reason: 'device 1 with the peer OWN key must still build',
      );

      served = mallory;
      enc.markSessionRebuild(peerId);

      await expectLater(
        enc.ensureSession(peerId),
        throwsA(isA<AccountIdentityMismatch>()),
      );
      expect(enc.peersWithChangedIdentity, contains(peerId));
    });

    test('POSITIVE CONTROL: the peer OWN key builds on a cold cache', () async {
      await pinPeerHonestly();
      expect(enc.cachedDeviceList(peerId), isNull);

      // THE RISK OF (lvi) IS EXACTLY THIS CASE. The account anchor is now
      // consulted for almost every send, so a bug here does not weaken
      // security — it blocks ordinary messaging for everyone.
      await expectLater(enc.ensureSession(peerId, deviceId: 2), completes);

      expect(
        await enc.encryptionService.peerIdentityAt(peerId, 2),
        await enc.encryptionService.peerTofuIdentityBase64(peerId),
        reason: 'a legitimate sibling device shares the account identity (§3)',
      );
      expect(enc.peersWithChangedIdentity, isEmpty);
    });

    test('POSITIVE CONTROL: genuine first contact stays TOFU', () async {
      // No anchor for this account at all, so there is nothing to compare and
      // the gate must stay trusting — first contact is irreducibly TOFU.
      expect(
        await enc.encryptionService.peerTofuIdentityBase64(peerId),
        isNull,
      );

      await expectLater(enc.ensureSession(peerId), completes);
      expect(enc.peersWithChangedIdentity, isEmpty);
    });
  });
}
