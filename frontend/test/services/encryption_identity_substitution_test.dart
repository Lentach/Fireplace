import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server-side key substitution (machine-in-the-middle) must be VISIBLE.
///
/// The server hands out prekey bundles and nothing in the protocol proves a
/// bundle belongs to the claimed user — only the identity-change warning stands
/// between a compromised server and silently readable future traffic. That
/// warning was unreachable on exactly this path until 2026-08-05:
/// `_buildSessionSerialized` pre-saved the bundle's identity key BEFORE
/// `processPreKeyBundle`, so libsignal's `isTrustedIdentity` read back the key
/// it had just written, took the `_sameIdentity` fast path, and never fired
/// `onIdentityChanged`.
///
/// These tests drive the REAL `buildSession` with a REAL substituted bundle, so
/// they fail if the pre-save (or any equivalent) ever comes back. Testing
/// `SecureIdentityKeyStore` directly does NOT cover this — the old bug lived in
/// the caller, and the store's own unit tests stayed green throughout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const aliceId = 1;
  const bobId = 2;
  // Mallory holds a DIFFERENT identity but is served to Alice under Bob's id,
  // which is precisely what a compromised server does.
  const malloryId = 3;

  late EncryptionService alice;
  late EncryptionService bob;
  late EncryptionService mallory;

  /// The FLAT bundle map `buildSession` expects, exactly as the server serves
  /// `fetchPreKeyBundle`.
  Map<String, dynamic> flatBundleFrom(EncryptionService peer) {
    final upload = peer.getKeysForUpload();
    expect(upload, isNotNull);
    final keyBundle = (upload!['keyBundle'] as Map).cast<String, dynamic>();
    final otps = (upload['oneTimePreKeys'] as List)
        .cast<Map<String, dynamic>>();
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
    alice = EncryptionService();
    bob = EncryptionService();
    mallory = EncryptionService();
    await alice.initialize(aliceId, checkServerBundleExists: () async => false);
    await bob.initialize(bobId, checkServerBundleExists: () async => false);
    await mallory.initialize(malloryId, checkServerBundleExists: () async => false);
  });

  group('peer identity substitution', () {
    test('first contact does NOT warn', () async {
      final warned = <int>[];
      alice.onPeerIdentityChanged = warned.add;

      await alice.buildSession(bobId, flatBundleFrom(bob));

      expect(alice.peersWithChangedIdentity, isEmpty);
      expect(warned, isEmpty, reason: 'TOFU first contact is silent by design');
    });

    test('a substituted identity for a known peer WARNS', () async {
      await alice.buildSession(bobId, flatBundleFrom(bob));
      expect(alice.peersWithChangedIdentity, isEmpty);

      final warned = <int>[];
      alice.onPeerIdentityChanged = warned.add;

      // The server now answers a bundle fetch for Bob with Mallory's identity.
      await alice.buildSession(bobId, flatBundleFrom(mallory));

      expect(
        alice.peersWithChangedIdentity,
        contains(bobId),
        reason: 'a key substitution for a known peer must be surfaced',
      );
      expect(warned, [bobId]);
    });

    test('the warning survives a restart until acknowledged', () async {
      await alice.buildSession(bobId, flatBundleFrom(bob));
      await alice.buildSession(bobId, flatBundleFrom(mallory));
      expect(alice.peersWithChangedIdentity, contains(bobId));

      // Same user, fresh process: the persisted warning must come back, or a
      // user who was not looking at that chat never learns it happened.
      final restarted = EncryptionService();
      await restarted.initialize(aliceId, checkServerBundleExists: () async => false);

      expect(restarted.peersWithChangedIdentity, contains(bobId));
    });

    test('acknowledging clears it, and it stays cleared after a restart',
        () async {
      await alice.buildSession(bobId, flatBundleFrom(bob));
      await alice.buildSession(bobId, flatBundleFrom(mallory));
      expect(alice.peersWithChangedIdentity, contains(bobId));

      await alice.acknowledgePeerIdentity(bobId);
      expect(alice.peersWithChangedIdentity, isEmpty);

      final restarted = EncryptionService();
      await restarted.initialize(aliceId, checkServerBundleExists: () async => false);
      expect(restarted.peersWithChangedIdentity, isEmpty);
    });

    test('acknowledging one peer leaves another peer\'s warning standing',
        () async {
      const carolId = 4;
      final carol = EncryptionService();
      await carol.initialize(carolId, checkServerBundleExists: () async => false);

      await alice.buildSession(bobId, flatBundleFrom(bob));
      await alice.buildSession(carolId, flatBundleFrom(carol));
      await alice.buildSession(bobId, flatBundleFrom(mallory));
      await alice.buildSession(carolId, flatBundleFrom(mallory));
      expect(alice.peersWithChangedIdentity, containsAll(<int>[bobId, carolId]));

      await alice.acknowledgePeerIdentity(bobId);

      expect(alice.peersWithChangedIdentity, contains(carolId));
      expect(alice.peersWithChangedIdentity, isNot(contains(bobId)));
    });
  });
}
