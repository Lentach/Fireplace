import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/services/passcode_kdf.dart';
import 'package:fireplace/services/passcode_store.dart';

/// Deterministic stand-in for PBKDF2: same contract (passcode + salt +
/// iterations in, stable bytes out), no native library. The real primitive is
/// covered by `test/services/passcode_kdf_test.dart` and the on-device run.
class FakePasscodeKdf implements PasscodeKdf {
  int calls = 0;
  bool broken = false;

  @override
  Future<Uint8List> derive({
    required String passcode,
    required Uint8List salt,
    required int iterations,
    int lengthBytes = 32,
  }) async {
    calls++;
    if (broken) throw StateError('webcrypto unavailable');
    final seed = utf8.encode('$passcode|${base64Encode(salt)}|$iterations');
    final out = Uint8List(lengthBytes);
    for (var i = 0; i < lengthBytes; i++) {
      out[i] = seed[i % seed.length] ^ (i * 31 & 0xff);
    }
    return out;
  }
}

/// In-memory [PasscodeStore] with the same visible semantics as
/// `DevicePasscodeStore` (which has its own tests against SharedPreferences).
class MemoryPasscodeStore implements PasscodeStore {
  PasscodeRecord record = PasscodeRecord.disabled;
  int credentialWrites = 0;

  @override
  Future<PasscodeRecord> load() async => record;

  @override
  Future<void> saveCredential({
    required PasscodeMode mode,
    required Uint8List salt,
    required Uint8List verifier,
    required int iterations,
  }) async {
    credentialWrites++;
    record = PasscodeRecord(
      enabled: true,
      mode: mode,
      salt: salt,
      verifier: verifier,
      iterations: iterations,
      autoLockSeconds: record.autoLockSeconds,
      lastActiveAtMs: record.lastActiveAtMs,
      failedAttempts: 0,
      lockoutUntilMs: null,
    );
  }

  @override
  Future<void> clearCredential() async {
    record = PasscodeRecord(
      enabled: false,
      mode: record.mode,
      salt: null,
      verifier: null,
      iterations: record.iterations,
      autoLockSeconds: record.autoLockSeconds,
      lastActiveAtMs: record.lastActiveAtMs,
      failedAttempts: 0,
      lockoutUntilMs: null,
    );
  }

  @override
  Future<void> saveAutoLockSeconds(int seconds) async {
    record = _copy(autoLockSeconds: seconds);
  }

  @override
  Future<void> saveLastActiveAt(int? epochMs) async {
    record = _copy(lastActiveAtMs: epochMs, clearLastActive: epochMs == null);
  }

  @override
  Future<void> saveAttemptState({
    required int failedAttempts,
    required int? lockoutUntilMs,
  }) async {
    record = _copy(
      failedAttempts: failedAttempts,
      lockoutUntilMs: lockoutUntilMs,
      clearLockout: lockoutUntilMs == null,
    );
  }

  PasscodeRecord _copy({
    int? autoLockSeconds,
    int? lastActiveAtMs,
    bool clearLastActive = false,
    int? failedAttempts,
    int? lockoutUntilMs,
    bool clearLockout = false,
  }) => PasscodeRecord(
    enabled: record.enabled,
    credentialDamaged: record.credentialDamaged,
    mode: record.mode,
    salt: record.salt,
    verifier: record.verifier,
    iterations: record.iterations,
    autoLockSeconds: autoLockSeconds ?? record.autoLockSeconds,
    lastActiveAtMs:
        clearLastActive ? null : (lastActiveAtMs ?? record.lastActiveAtMs),
    failedAttempts: failedAttempts ?? record.failedAttempts,
    lockoutUntilMs:
        clearLockout ? null : (lockoutUntilMs ?? record.lockoutUntilMs),
  );
}
