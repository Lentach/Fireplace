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
      await service.initialize(17);

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

  test(
    'returns null when no trusted identity is stored for the peer',
    () async {
      final service = EncryptionService();
      await service.initialize(17);

      expect(await service.getPeerIdentityFingerprint(42), isNull);
    },
  );

  test('returns null before E2E initialization', () async {
    final service = EncryptionService();

    expect(await service.getPeerIdentityFingerprint(42), isNull);
  });
}
