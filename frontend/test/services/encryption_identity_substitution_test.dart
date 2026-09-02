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

      await alice.buildSession(bobId, flatBundleFrom(bob), expectedIdentityBase64: null);

      expect(alice.peersWithChangedIdentity, isEmpty);
      expect(warned, isEmpty, reason: 'TOFU first contact is silent by design');
    });

    test('a substituted identity for a known peer WARNS', () async {
      await alice.buildSession(bobId, flatBundleFrom(bob), expectedIdentityBase64: null);
      expect(alice.peersWithChangedIdentity, isEmpty);

      final warned = <int>[];
      alice.onPeerIdentityChanged = warned.add;

      // The server now answers a bundle fetch for Bob with Mallory's identity.
      await alice.buildSession(bobId, flatBundleFrom(mallory), expectedIdentityBase64: null);

      expect(
        alice.peersWithChangedIdentity,
        contains(bobId),
        reason: 'a key substitution for a known peer must be surfaced',
      );
      expect(warned, [bobId]);
    });

    test('the warning survives a restart until acknowledged', () async {
      await alice.buildSession(bobId, flatBundleFrom(bob), expectedIdentityBase64: null);
      await alice.buildSession(bobId, flatBundleFrom(mallory), expectedIdentityBase64: null);
      expect(alice.peersWithChangedIdentity, contains(bobId));

      // Same user, fresh process: the persisted warning must come back, or a
      // user who was not looking at that chat never learns it happened.
      final restarted = EncryptionService();
      await restarted.initialize(aliceId, checkServerBundleExists: () async => false);

      expect(restarted.peersWithChangedIdentity, contains(bobId));
    });

    test('acknowledging clears it, and it stays cleared after a restart',
        () async {
      await alice.buildSession(bobId, flatBundleFrom(bob), expectedIdentityBase64: null);
      await alice.buildSession(bobId, flatBundleFrom(mallory), expectedIdentityBase64: null);
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

      await alice.buildSession(bobId, flatBundleFrom(bob), expectedIdentityBase64: null);
      await alice.buildSession(carolId, flatBundleFrom(carol), expectedIdentityBase64: null);
      await alice.buildSession(bobId, flatBundleFrom(mallory), expectedIdentityBase64: null);
      await alice.buildSession(carolId, flatBundleFrom(mallory), expectedIdentityBase64: null);
      expect(alice.peersWithChangedIdentity, containsAll(<int>[bobId, carolId]));

      await alice.acknowledgePeerIdentity(bobId);

      expect(alice.peersWithChangedIdentity, contains(carolId));
      expect(alice.peersWithChangedIdentity, isNot(contains(bobId)));
    });
  });

  /// The SECOND hole, closed by spec §12 amendment (xxxix).
  ///
  /// The group above defends the SAME address: a key that changes where one was
  /// already known. It cannot see this one. §3 says every device of an account
  /// shares ONE identity key, but TOFU is keyed per `(peer, deviceId)`, so a
  /// peer's NEWLY LINKED device is a fresh address — `existing == null`, nothing
  /// to compare, trusted in silence. A server that cannot forge the DAK-signed
  /// device list could still serve its own identity for a device that list
  /// legitimately names, which is a silent MITM slot on every link.
  group('account-wide identity binding (amendment (xxxix))', () {
    test('a NEW device of a known peer carrying a foreign identity is REFUSED',
        () async {
      // Alice knows Bob's device 1 the honest way.
      await alice.buildSession(
        bobId,
        flatBundleFrom(bob),
        expectedIdentityBase64: null,
      );
      final anchor = await alice.peerIdentityAt(bobId, 1);
      expect(anchor, isNotNull, reason: 'device 1 is the account anchor here');

      // The server now claims Bob linked device 2, and serves MALLORY's key
      // for it. The device list would happily name device 2; only the identity
      // binding can tell that this bundle is not Bob's.
      await expectLater(
        alice.buildSession(
          bobId,
          flatBundleFrom(mallory),
          deviceId: 2,
          expectedIdentityBase64: anchor,
        ),
        throwsA(isA<AccountIdentityMismatch>()),
      );

      // Fail CLOSED: nothing was trusted and nothing was stored, so a retry
      // cannot find the attacker's key already in place.
      expect(await alice.peerIdentityAt(bobId, 2), isNull);
    });

    // (lv) Finding F5. Failing closed is right; failing closed SILENTLY made
    // the chat a permanent unexplained outage, because the banner is the only
    // door to the out-of-band comparison that repairs it.
    test('the refusal RAISES the identity surface, so the ceremony is reachable',
        () async {
      final warned = <int>[];
      alice.onPeerIdentityChanged = warned.add;

      await alice.buildSession(
        bobId,
        flatBundleFrom(bob),
        expectedIdentityBase64: null,
      );
      final anchor = await alice.peerIdentityAt(bobId, 1);
      expect(alice.peersWithChangedIdentity, isEmpty);

      await expectLater(
        alice.buildSession(
          bobId,
          flatBundleFrom(mallory),
          deviceId: 2,
          expectedIdentityBase64: anchor,
        ),
        throwsA(isA<AccountIdentityMismatch>()),
      );

      // The banner exists and the UI was told, or the user sees a dead chat.
      expect(alice.peersWithChangedIdentity, contains(bobId));
      expect(warned, contains(bobId));
      // Still fail-closed: raising the alarm must not have trusted anything.
      expect(await alice.peerIdentityAt(bobId, 2), isNull);
    });

    test('the refused key is STAGED, so the ceremony has a candidate to adopt',
        () async {
      await alice.buildSession(
        bobId,
        flatBundleFrom(bob),
        expectedIdentityBase64: null,
      );
      final anchor = await alice.peerIdentityAt(bobId, 1);

      await expectLater(
        alice.buildSession(
          bobId,
          flatBundleFrom(mallory),
          deviceId: 2,
          expectedIdentityBase64: anchor,
        ),
        throwsA(isA<AccountIdentityMismatch>()),
      );

      // The staged candidate is what an adoption promotes, which keeps "the
      // pinned key is the key the human was shown" structural ((xlvii) cl. 3).
      // No servedIdentityBase64 is passed, so a candidate can only come from
      // the slot the refusal itself staged.
      final verification = await alice.peerIdentityVerification(bobId);
      expect(
        verification.offeredFingerprint,
        isNotNull,
        reason: 'the offered key must be recorded for the comparison',
      );
      expect(
        verification.offeredIdentityBase64,
        flatBundleFrom(mallory)['identityPublicKey'],
        reason: 'the candidate must be exactly the key that was refused',
      );
      expect(
        verification.offeredFingerprint,
        isNot(verification.pinnedFingerprint),
        reason: 'a candidate equal to the pin would be nothing to decide',
      );
    });

    test('a NEW device carrying the ACCOUNT identity is accepted, silently',
        () async {
      await alice.buildSession(
        bobId,
        flatBundleFrom(bob),
        expectedIdentityBase64: null,
      );
      final anchor = await alice.peerIdentityAt(bobId, 1);

      final warned = <int>[];
      alice.onPeerIdentityChanged = warned.add;

      // The legitimate case the feature exists for: Bob linked a real second
      // device, so the bundle carries the SAME account identity key.
      await alice.buildSession(
        bobId,
        flatBundleFrom(bob),
        deviceId: 2,
        expectedIdentityBase64: anchor,
      );

      expect(await alice.peerIdentityAt(bobId, 2), anchor);
      expect(
        warned,
        isEmpty,
        reason: 'linking a device is normal and must not cry wolf',
      );
      expect(alice.peersWithChangedIdentity, isEmpty);
    });

    test('a null anchor still means TOFU — first contact with an ACCOUNT',
        () async {
      // No anchor exists because Alice has never met this account on any
      // device. That is irreducibly trust-on-first-use and must keep working,
      // or no one could ever start a conversation.
      await alice.buildSession(
        bobId,
        flatBundleFrom(bob),
        deviceId: 3,
        expectedIdentityBase64: null,
      );

      expect(await alice.peerIdentityAt(bobId, 3), isNotNull);
    });
  });
}
