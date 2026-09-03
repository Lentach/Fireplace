import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/passcode_store.dart';
import 'package:fireplace/services/secure_kv.dart';
import 'package:fireplace/utils/passcode_autolock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureKv implements SecureKv {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DevicePasscodeStore on virgin storage', () {
    test('reports disabled with the default auto-lock and no attempt state',
        () async {
      final record = await DevicePasscodeStore(useSecureStorage: false).load();

      expect(record.enabled, isFalse);
      expect(record.salt, isNull);
      expect(record.verifier, isNull);
      expect(record.autoLockSeconds, kPasscodeAutoLockDefaultSeconds);
      expect(record.lastActiveAtMs, isNull);
      expect(record.failedAttempts, 0);
      expect(record.lockoutUntilMs, isNull);
    });
  });

  group('DevicePasscodeStore credential round trip', () {
    test('a saved credential loads back byte-identical', () async {
      final store = DevicePasscodeStore(useSecureStorage: false);
      await store.saveCredential(
        mode: PasscodeMode.digits6,
        salt: _bytes(const [1, 2, 3, 4]),
        verifier: _bytes(const [9, 8, 7]),
        iterations: 1234,
      );

      final record = await DevicePasscodeStore(useSecureStorage: false).load();

      expect(record.enabled, isTrue);
      expect(record.mode, PasscodeMode.digits6);
      expect(record.salt, _bytes(const [1, 2, 3, 4]));
      expect(record.verifier, _bytes(const [9, 8, 7]));
      expect(record.iterations, 1234);
    });

    test('each mode survives the round trip', () async {
      for (final mode in PasscodeMode.values) {
        SharedPreferences.setMockInitialValues({});
        final store = DevicePasscodeStore(useSecureStorage: false);
        await store.saveCredential(
          mode: mode,
          salt: _bytes(const [1]),
          verifier: _bytes(const [2]),
          iterations: 1,
        );
        expect((await store.load()).mode, mode);
      }
    });

    test('clearCredential disables and drops the secret AND attempt state',
        () async {
      final store = DevicePasscodeStore(useSecureStorage: false);
      await store.saveCredential(
        mode: PasscodeMode.digits4,
        salt: _bytes(const [1]),
        verifier: _bytes(const [2]),
        iterations: 1,
      );
      await store.saveAttemptState(failedAttempts: 4, lockoutUntilMs: 999);

      await store.clearCredential();
      final record = await store.load();

      expect(record.enabled, isFalse);
      expect(record.salt, isNull);
      expect(record.verifier, isNull);
      expect(record.failedAttempts, 0);
      expect(record.lockoutUntilMs, isNull);
    });
  });

  group('DevicePasscodeStore mutable state', () {
    test('auto-lock seconds persist', () async {
      final store = DevicePasscodeStore(useSecureStorage: false);
      await store.saveAutoLockSeconds(3600);
      expect((await store.load()).autoLockSeconds, 3600);
    });

    test('the last-active stamp persists and can be cleared', () async {
      final store = DevicePasscodeStore(useSecureStorage: false);
      await store.saveLastActiveAt(1757000000000);
      expect((await store.load()).lastActiveAtMs, 1757000000000);

      await store.saveLastActiveAt(null);
      expect((await store.load()).lastActiveAtMs, isNull);
    });

    test('attempt state persists across store instances', () async {
      await DevicePasscodeStore(useSecureStorage: false)
          .saveAttemptState(failedAttempts: 3, lockoutUntilMs: 42);

      final record = await DevicePasscodeStore(useSecureStorage: false).load();
      expect(record.failedAttempts, 3);
      expect(record.lockoutUntilMs, 42);
    });
  });

  group('DevicePasscodeStore secure-storage path (Android)', () {
    test('salt and verifier go to secure storage, never to prefs', () async {
      final secure = _FakeSecureKv();
      final store = DevicePasscodeStore(secure: secure, useSecureStorage: true);
      await store.saveCredential(
        mode: PasscodeMode.alphanumeric,
        salt: _bytes(const [5, 5]),
        verifier: _bytes(const [6, 6]),
        iterations: 7,
      );

      expect(secure.values.keys, contains(DevicePasscodeStore.saltKey));
      expect(secure.values.keys, contains(DevicePasscodeStore.verifierKey));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DevicePasscodeStore.saltKey), isNull);
      expect(prefs.getString(DevicePasscodeStore.verifierKey), isNull);

      final record = await store.load();
      expect(record.enabled, isTrue);
      expect(record.verifier, _bytes(const [6, 6]));
      expect(record.mode, PasscodeMode.alphanumeric);
    });

    test('clearCredential deletes the secure secrets too', () async {
      final secure = _FakeSecureKv();
      final store = DevicePasscodeStore(secure: secure, useSecureStorage: true);
      await store.saveCredential(
        mode: PasscodeMode.digits4,
        salt: _bytes(const [1]),
        verifier: _bytes(const [2]),
        iterations: 1,
      );

      await store.clearCredential();

      expect(secure.values, isEmpty);
      expect((await store.load()).enabled, isFalse);
    });
  });

  group('DevicePasscodeStore damaged credential', () {
    // The flag READ TRUE, so a passcode exists and only its verifier is
    // missing. Reporting that as "no passcode" would let a wiped or tampered
    // Keystore entry silently UNLOCK the app — the error-as-absence
    // inversion `AuthTokenStore` was hardened against. It is reported as
    // damaged so the gate can fail CLOSED and route the user to recovery.
    test('a flag with a missing verifier reads as damaged, not disabled',
        () async {
      final store = DevicePasscodeStore(useSecureStorage: false);
      await store.saveCredential(
        mode: PasscodeMode.digits6,
        salt: _bytes(const [1]),
        verifier: _bytes(const [2]),
        iterations: 1,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(DevicePasscodeStore.verifierKey);

      final record = await store.load();
      expect(record.credentialDamaged, isTrue);
      expect(record.enabled, isFalse, reason: 'nothing can be verified');
      expect(record.verifier, isNull);
    });

    test('a missing salt is damaged too', () async {
      final store = DevicePasscodeStore(useSecureStorage: false);
      await store.saveCredential(
        mode: PasscodeMode.digits4,
        salt: _bytes(const [1]),
        verifier: _bytes(const [2]),
        iterations: 1,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(DevicePasscodeStore.saltKey);

      expect((await store.load()).credentialDamaged, isTrue);
    });

    test('no flag at all is plain disabled, never damaged', () async {
      final record = await DevicePasscodeStore(useSecureStorage: false).load();
      expect(record.enabled, isFalse);
      expect(record.credentialDamaged, isFalse);
    });
  });
}
