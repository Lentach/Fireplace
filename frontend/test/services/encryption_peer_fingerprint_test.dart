import 'dart:convert';

import 'package:fireplace/services/encryption/signal_stores.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fingerprints are only useful when the peer value is rendered exactly like
/// the user's own value. Store the user's public identity as a peer identity:
/// identical key bytes make this assertion independent of a duplicated test
/// formatter and catch any future drift between the two display paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secure = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'formats a stored peer identity exactly like the own identity',
    () async {
      final service = EncryptionService();
      await service.initialize(17, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));

      final ownFingerprint = await service.getIdentityFingerprint();
      final ownKeyBase64 = await service.currentIdentityPublicKeyBase64();
      final ownKey = IdentityKey.fromBytes(base64Decode(ownKeyBase64!), 0);
      final peerStore = SecureIdentityKeyStore(DualStorage(secure), 'e2e_17_');
      await peerStore.saveIdentity(SignalProtocolAddress('42', 1), ownKey);

      final peerFingerprint = await service.getPeerIdentityFingerprint(42);

      expect(peerFingerprint, ownFingerprint);
      expect(peerFingerprint, isNotNull);
      final groups = peerFingerprint!.split(' ');
      expect(groups.last.length, lessThanOrEqualTo(4));
      expect(groups.take(groups.length - 1), everyElement(hasLength(4)));
      expect(peerFingerprint, peerFingerprint.toLowerCase());
    },
  );

  /// D2 / (xlvii) clause 2. The displayed number MUST follow the ACCOUNT
  /// anchor. It used to read a fixed `(peer, device 1)` address, which was
  /// wrong twice over: the account row is the ONLY thing an acknowledgement
  /// moves, so the two diverged permanently after any accepted change, and a
  /// post-§6.2 peer has no device 1 at all because ids are never reused.
  /// The one out-of-band MITM check therefore showed a stale number — or none —
  /// exactly for the accounts that had most recently survived a takeover.
  ///
  /// Rendered fingerprints are compared against OTHER peers holding the same
  /// key rather than a hand-built string: that keeps the assertion independent
  /// of a duplicated test formatter.
  test('follows the account anchor, not a stale device-1 row', () async {
    final service = EncryptionService();
    await service.initialize(17, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    final store = SecureIdentityKeyStore(DualStorage(secure), 'e2e_17_');

    final oldKey = generateIdentityKeyPair().getPublicKey();
    final newKey = generateIdentityKeyPair().getPublicKey();

    // The peer as we first met them. saveIdentity pins the account anchor too.
    await store.saveIdentity(SignalProtocolAddress('42', 1), oldKey);
    // They rotate and a human accepts it: ONLY the account row advances, which
    // is the divergence the old address could not see.
    await store.adoptAccountIdentity('42', newKey, expectedPendingBase64: null);

    // Reference renderings of each key, via peers whose only key is that one.
    await store.adoptAccountIdentity('43', newKey, expectedPendingBase64: null);
    await store.saveIdentity(SignalProtocolAddress('44', 1), oldKey);

    expect(
      await service.getPeerIdentityFingerprint(42),
      await service.getPeerIdentityFingerprint(43),
      reason: 'the accepted account key is what the user must compare',
    );
    expect(
      await service.getPeerIdentityFingerprint(42),
      isNot(await service.getPeerIdentityFingerprint(44)),
      reason:
          'pre-fix this read the device-1 row and rendered the SUPERSEDED '
          'key, so the user compared a number the peer no longer had',
    );
  });

  /// The other half of D2: a peer who completed §6.2 has no device 1, so the
  /// old fixed address returned nothing and the dialog said "no stored
  /// identity key" for a peer we were actively talking to.
  test('shows a fingerprint for a peer with no device 1 at all', () async {
    final service = EncryptionService();
    await service.initialize(17, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));
    final store = SecureIdentityKeyStore(DualStorage(secure), 'e2e_17_');

    // Ids are never reused ((a)): a post-reset account is met on a high id.
    await store.saveIdentity(
      SignalProtocolAddress('42', 5),
      generateIdentityKeyPair().getPublicKey(),
    );

    expect(
      await service.getPeerIdentityFingerprint(42),
      isNotNull,
      reason:
          'pre-fix the fixed (peer, 1) address was empty for exactly the '
          'accounts that had most recently survived a takeover',
    );
  });

  test(
    'returns null when no trusted identity is stored for the peer',
    () async {
      final service = EncryptionService();
      await service.initialize(17, checkServerIdentity: () async => const ServerIdentityGuard(exists: false));

      expect(await service.getPeerIdentityFingerprint(42), isNull);
    },
  );

  test('returns null before E2E initialization', () async {
    final service = EncryptionService();

    expect(await service.getPeerIdentityFingerprint(42), isNull);
  });
}
