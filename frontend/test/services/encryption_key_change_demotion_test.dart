import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Amendment (lxxix): the peer key-change surface is DEMOTED by default.
///
/// With `keyChangeWarnings` OFF (the default predicate), a locally detected
/// peer identity change auto-acknowledges: the I7 account anchor advances to
/// the new key through the SAME [EncryptionService.acknowledgePeerIdentity]
/// compare-and-swap the manual ceremony uses, and a one-shot muted note
/// ({peerId, occurredAt}) is persisted so the timeline line survives a reload
/// (falsification F12). With the predicate ON, today's manual-confirmation
/// behaviour is unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const aliceId = 1;
  const bobId = 2;
  const malloryId = 3;

  late EncryptionService alice;
  late EncryptionService bob;
  late EncryptionService mallory;

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
    await alice.initialize(aliceId,
        checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    await bob.initialize(bobId,
        checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    await mallory.initialize(malloryId,
        checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
  });

  test(
      'F12: setting OFF — a local key change auto-acks, advances the anchor '
      'and persists the note across a service relaunch', () async {
    await alice.buildSession(bobId, flatBundleFrom(bob),
        expectedIdentityBase64: null);
    expect(alice.peerKeyChangeNotes, isEmpty);

    final substituted = flatBundleFrom(mallory);
    await alice.buildSession(bobId, substituted,
        expectedIdentityBase64: null);
    // The demotion runs fire-and-forget off the store callback; drain it.
    await pumpEventQueue();

    expect(
      alice.peersWithChangedIdentity,
      isEmpty,
      reason: 'with warnings demoted the change is acknowledged at once',
    );
    expect(
      await alice.peerTofuIdentityBase64(bobId),
      substituted['identityPublicKey'],
      reason: 'the I7 anchor must advance to the new key (auto-ack removed '
          '→ this assertion fails with the old pinned key)',
    );
    expect(alice.peerKeyChangeNotes, contains(bobId));
    expect(
      DateTime.tryParse(alice.peerKeyChangeNotes[bobId]!),
      isNotNull,
      reason: 'occurredAt is a parseable instant',
    );

    // The relaunch: a SECOND service over the same prefs still lists the note
    // and revives no warning (F12: the muted line persists across reload).
    final restarted = EncryptionService();
    await restarted.initialize(aliceId,
        checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    expect(restarted.peerKeyChangeNotes, contains(bobId));
    expect(restarted.peersWithChangedIdentity, isEmpty);
  });

  test('setting ON — today\'s manual warning stands and no note is recorded',
      () async {
    alice.keyChangeWarnings = () => true;
    await alice.buildSession(bobId, flatBundleFrom(bob),
        expectedIdentityBase64: null);
    final pinned = await alice.peerTofuIdentityBase64(bobId);

    await alice.buildSession(bobId, flatBundleFrom(mallory),
        expectedIdentityBase64: null);
    await pumpEventQueue();

    expect(
      alice.peersWithChangedIdentity,
      contains(bobId),
      reason: 'toggle ignored → the warning would vanish (F11 service half)',
    );
    expect(await alice.peerTofuIdentityBase64(bobId), pinned,
        reason: 'no human confirmed, so the anchor must not move');
    expect(alice.peerKeyChangeNotes, isEmpty);
  });

  test('setting OFF — the server-event path records a persisted note too',
      () async {
    await alice.buildSession(bobId, flatBundleFrom(bob),
        expectedIdentityBase64: null);

    await alice.recordPeerIdentityChangedFromServer(bobId);

    expect(alice.peerKeyChangeNotes, contains(bobId));
    final restarted = EncryptionService();
    await restarted.initialize(aliceId,
        checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    expect(restarted.peerKeyChangeNotes, contains(bobId));
  });
  test(
      'setting OFF — an account-identity refusal ((lv)) is NOT demoted: '
      'fail-closed, no auto-ack, no note, refused-set raised', () async {
    await alice.buildSession(bobId, flatBundleFrom(bob),
        expectedIdentityBase64: null);
    final pinned = await alice.peerTofuIdentityBase64(bobId);

    // The (xxxix)/(lv) gate: the served bundle carries a foreign identity.
    await expectLater(
      alice.buildSession(bobId, flatBundleFrom(mallory),
          expectedIdentityBase64: pinned),
      throwsA(isA<AccountIdentityMismatch>()),
    );

    expect(await alice.peerTofuIdentityBase64(bobId), pinned,
        reason: 'auto-adopting a key the anchor just refused would convert a '
            'live MITM refusal into silent trust');
    expect(alice.peerKeyChangeNotes, isEmpty,
        reason: 'a refused peer never gets the muted note');
    expect(
      alice.peersRefusedIdentity,
      contains(bobId),
      reason: 'the refusal must raise the always-on pill surface, or the '
          'muted default leaves a blocked chat with zero UI',
    );
    expect(alice.peersWithChangedIdentity, contains(bobId));

    // The ceremony is the door: a confirmed acknowledgement of the staged
    // offer advances the anchor and clears BOTH surfaces.
    final acked = await alice.acknowledgePeerIdentity(bobId);
    expect(acked, isTrue);
    expect(alice.peersRefusedIdentity, isEmpty,
        reason: 'the pill must come down once the human resolved it');
    expect(alice.peersWithChangedIdentity, isEmpty);
  });

  test('setting ON — the refusal is identical: fail-closed with the pill set',
      () async {
    alice.keyChangeWarnings = () => true;
    await alice.buildSession(bobId, flatBundleFrom(bob),
        expectedIdentityBase64: null);
    final pinned = await alice.peerTofuIdentityBase64(bobId);

    await expectLater(
      alice.buildSession(bobId, flatBundleFrom(mallory),
          expectedIdentityBase64: pinned),
      throwsA(isA<AccountIdentityMismatch>()),
    );

    expect(await alice.peerTofuIdentityBase64(bobId), pinned);
    expect(alice.peersWithChangedIdentity, contains(bobId));
    expect(alice.peersRefusedIdentity, contains(bobId));
    expect(alice.peerKeyChangeNotes, isEmpty);
  });
}
