import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Crypto-layer proof of the 2026-07-11 stale-OTP bad-MAC mechanism, using the
/// app's REAL [EncryptionService] (real libsignal X3DH + Double Ratchet — no
/// crypto mocking).
///
/// The field failure: after a recipient regenerates their Signal identity
/// (fresh install / key loss), the server kept the recipient's OLD unused
/// one-time pre-keys and — post-0.0.96 — served them oldest-first inside the
/// recipient's CURRENT bundle. A sender then builds X3DH with the current
/// identity/signed-pre-key but a DEAD one-time pre-key whose private half the
/// recipient discarded. The recipient cannot reproduce the X3DH secret ->
/// PreKey (type 3) message fails the MAC check -> persistent [Decryption failed].
///
/// This pins that mechanism (RED) and proves that serving a CURRENT-epoch OTP —
/// what the server now guarantees via the identityPublicKey fetch filter —
/// decrypts cleanly (GREEN).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const aliceId = 1; // the recipient who regenerates identity
  const bobStaleId = 2; // sender served a STALE OTP
  const bobFreshId = 3; // sender served a CURRENT-epoch OTP

  Map<String, dynamic> flatBundle(
    EncryptionService peer, {
    int? overrideOtpId,
    String? overrideOtpPublic,
  }) {
    final upload = peer.getKeysForUpload()!;
    final keyBundle = (upload['keyBundle'] as Map).cast<String, dynamic>();
    final otps = (upload['oneTimePreKeys'] as List).cast<Map<String, dynamic>>();
    final otp = otps.first;
    return {
      ...keyBundle,
      'oneTimePreKeyId': overrideOtpId ?? otp['keyId'],
      'oneTimePreKeyPublic': overrideOtpPublic ?? otp['publicKey'],
    };
  }

  late EncryptionService alice;
  late Map<String, dynamic> staleOtp; // epoch-1 one-time pre-key (public+id)
  late String epoch1Identity;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});

    // Epoch 1: alice's original identity + one-time pre-keys.
    alice = EncryptionService();
    await alice.initialize(aliceId, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    final v1 = flatBundle(alice);
    epoch1Identity = v1['identityPublicKey'] as String;
    staleOtp = {
      'keyId': v1['oneTimePreKeyId'],
      'publicKey': v1['oneTimePreKeyPublic'],
    };

    // Regenerate identity (fresh install / storage loss), SAME account id.
    // alice now holds ONLY epoch-2 private keys; the epoch-1 OTP private is gone.
    await alice.clearAllKeys();
    await alice.initialize(aliceId, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
  });

  test('epoch-2 identity differs from epoch-1 (regeneration really happened)',
      () async {
    final v2 = flatBundle(alice);
    expect(v2['identityPublicKey'], isNot(epoch1Identity),
        reason: 'clearAllKeys + re-init must mint a new identity epoch');
  });

  test('RED: a stale-epoch OTP inside the current bundle -> PreKey Bad Mac',
      () async {
    // Poisoned bundle = alice's CURRENT (epoch-2) identity/signed-pre-key but the
    // STALE epoch-1 one-time pre-key — exactly what the pre-fix server served.
    final poisoned = flatBundle(
      alice,
      overrideOtpId: staleOtp['keyId'] as int,
      overrideOtpPublic: staleOtp['publicKey'] as String,
    );

    final bob = EncryptionService();
    await bob.initialize(bobStaleId, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    await bob.buildSession(aliceId, poisoned, expectedIdentityBase64: null);

    final wire = await bob.encrypt(aliceId, 'this must fail to decrypt');
    expect(wire.startsWith('3:'), isTrue,
        reason: 'X3DH opener is a PreKey (type 3) message');

    // alice lacks the epoch-1 OTP private -> cannot derive the X3DH secret.
    await expectLater(
      alice.decrypt(bobStaleId, wire),
      throwsA(anything),
      reason: 'stale one-time pre-key must fail the PreKey MAC check',
    );
  });

  test('GREEN: a current-epoch OTP inside the current bundle -> decrypts',
      () async {
    // Clean bundle = alice's current epoch-2 identity AND a current epoch-2 OTP
    // (what the identity-filtered fetch now guarantees the server serves).
    final clean = flatBundle(alice);

    final bob = EncryptionService();
    await bob.initialize(bobFreshId, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    await bob.buildSession(aliceId, clean, expectedIdentityBase64: null);

    const plaintext = 'current-epoch OTP decrypts cleanly';
    final wire = await bob.encrypt(aliceId, plaintext);
    expect(wire.startsWith('3:'), isTrue);

    expect(await alice.decrypt(bobFreshId, wire), plaintext,
        reason: 'current-epoch one-time pre-key completes X3DH');
  });
}
