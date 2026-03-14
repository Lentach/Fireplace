import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:fireplace/services/encryption/signal_stores.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureIdentityKeyStore.isTrustedIdentity', () {
    late SecureIdentityKeyStore store;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = DualStorage(const FlutterSecureStorage());
      store = SecureIdentityKeyStore(storage, 'test_');
    });

    test('trusts first-time identity (TOFU)', () async {
      final keyPair = generateIdentityKeyPair();
      final address = SignalProtocolAddress('user1', 1);
      final result = await store.isTrustedIdentity(
          address, keyPair.getPublicKey(), Direction.sending);
      expect(result, isTrue);
    });

    test('trusts same identity seen again', () async {
      final keyPair = generateIdentityKeyPair();
      final address = SignalProtocolAddress('user1', 1);
      await store.saveIdentity(address, keyPair.getPublicKey());
      final result = await store.isTrustedIdentity(
          address, keyPair.getPublicKey(), Direction.sending);
      expect(result, isTrue);
    });

    test('accepts new identity from peer who rotated keys', () async {
      final oldKeyPair = generateIdentityKeyPair();
      final address = SignalProtocolAddress('user1', 1);
      await store.saveIdentity(address, oldKeyPair.getPublicKey());

      // Peer regenerated keys (storage eviction / reinstall)
      final newKeyPair = generateIdentityKeyPair();

      final result = await store.isTrustedIdentity(
          address, newKeyPair.getPublicKey(), Direction.receiving);

      // Should accept key rotation — currently returns false (BUG)
      expect(result, isTrue);
    });

    test('stores updated identity after key rotation so next check also trusts it', () async {
      final oldKeyPair = generateIdentityKeyPair();
      final address = SignalProtocolAddress('user1', 1);
      await store.saveIdentity(address, oldKeyPair.getPublicKey());

      final newKeyPair = generateIdentityKeyPair();
      await store.isTrustedIdentity(
          address, newKeyPair.getPublicKey(), Direction.receiving);

      // After rotation, subsequent messages from same peer also trusted
      final result = await store.isTrustedIdentity(
          address, newKeyPair.getPublicKey(), Direction.receiving);
      expect(result, isTrue);
    });
  });
}
