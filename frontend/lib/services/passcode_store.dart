import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/e2e_persistent_diag.dart';
import '../utils/passcode_autolock.dart';
import 'passcode_kdf.dart';
import 'secure_kv.dart';

/// Passcode shape the user picked (Zangi parity, owner ruling 2026-09-03).
enum PasscodeMode {
  digits4,
  digits6,
  alphanumeric;

  /// Fixed length for the numeric modes; null means variable length, which is
  /// what makes the alphanumeric mode need an explicit submit action.
  int? get fixedLength => switch (this) {
    PasscodeMode.digits4 => 4,
    PasscodeMode.digits6 => 6,
    PasscodeMode.alphanumeric => null,
  };

  bool get isNumeric => fixedLength != null;

  static PasscodeMode fromStorage(String? raw) => switch (raw) {
    'digits4' => PasscodeMode.digits4,
    'alphanumeric' => PasscodeMode.alphanumeric,
    _ => PasscodeMode.digits6,
  };

  String get storageValue => name;
}

/// Everything the lock needs, as one immutable snapshot read in a single pass.
@immutable
class PasscodeRecord {
  const PasscodeRecord({
    required this.enabled,
    required this.mode,
    required this.salt,
    required this.verifier,
    required this.iterations,
    required this.autoLockSeconds,
    required this.lastActiveAtMs,
    required this.failedAttempts,
    required this.lockoutUntilMs,
    this.credentialDamaged = false,
  });

  static const PasscodeRecord disabled = PasscodeRecord(
    enabled: false,
    mode: PasscodeMode.digits6,
    salt: null,
    verifier: null,
    iterations: kPasscodeKdfIterations,
    autoLockSeconds: kPasscodeAutoLockDefaultSeconds,
    lastActiveAtMs: null,
    failedAttempts: 0,
    lockoutUntilMs: null,
  );

  final bool enabled;

  /// The enabled flag is set but the salt/verifier could not be read: a
  /// passcode EXISTS and cannot be checked. The gate must stay closed and
  /// route the user to recovery — never treat this as "no passcode".
  final bool credentialDamaged;

  final PasscodeMode mode;
  final Uint8List? salt;
  final Uint8List? verifier;
  final int iterations;
  final int autoLockSeconds;
  final int? lastActiveAtMs;
  final int failedAttempts;
  final int? lockoutUntilMs;
}

/// Durable home of the passcode credential and lock bookkeeping.
///
/// Abstract so the provider's state machine is testable without any platform
/// channel — the same reason `ContentSealer` and `SecureKv` are seams.
abstract class PasscodeStore {
  Future<PasscodeRecord> load();

  Future<void> saveCredential({
    required PasscodeMode mode,
    required Uint8List salt,
    required Uint8List verifier,
    required int iterations,
  });

  /// Disables the lock and destroys the credential AND the attempt state.
  Future<void> clearCredential();

  Future<void> saveAutoLockSeconds(int seconds);

  /// null clears the stamp, which [shouldLockOnForeground] treats as "lock".
  Future<void> saveLastActiveAt(int? epochMs);

  Future<void> saveAttemptState({
    required int failedAttempts,
    required int? lockoutUntilMs,
  });
}

/// Production store. Non-secret bookkeeping always lives in SharedPreferences;
/// the salt and verifier go to `flutter_secure_storage` on real Android only.
///
/// Same platform rule and the same reasoning as [AuthTokenStore]: Android is
/// the only shipped native target and its secure storage is genuinely
/// Keystore-backed, while on web `flutter_secure_storage_web` keeps its own
/// master key in the very localStorage it encrypts (see
/// `services/encryption/signal_stores.dart` class doc) — so there it would be
/// obfuscation with extra failure modes, not protection. That is exactly why
/// v1 is scoped as a UI gate: on web the verifier is readable, and the honest
/// claim is "stops a person holding your phone", not "stops forensics".
class DevicePasscodeStore implements PasscodeStore {
  DevicePasscodeStore({SecureKv? secure, bool? useSecureStorage})
    : _secure = secure ?? const FlutterSecureStorageKv(FlutterSecureStorage()),
      _useSecure = useSecureStorage ?? (!kIsWeb && Platform.isAndroid);

  final SecureKv _secure;
  final bool _useSecure;

  static const String enabledKey = 'passcode_enabled';
  static const String modeKey = 'passcode_mode';
  static const String autoLockKey = 'passcode_auto_lock_seconds';
  static const String lastActiveKey = 'passcode_last_active_at';
  static const String failedAttemptsKey = 'passcode_failed_attempts';
  static const String lockoutUntilKey = 'passcode_lockout_until';

  /// Secret half. Names carry the `fp_` prefix of the other secure-storage
  /// families so an inventory of the Keystore namespace stays readable.
  static const String saltKey = 'fp_passcode_salt_v1';
  static const String verifierKey = 'fp_passcode_verifier_v1';
  static const String iterationsKey = 'fp_passcode_iterations_v1';

  /// Retry cadence for the SECRET half, mirroring `AuthTokenStore.read`:
  /// Android Keystore reads fail transiently (after OS updates, backup
  /// restores, early-boot contention). A hiccup must not be mistaken for a
  /// damaged credential, because that costs the user a lock screen no code
  /// can open.
  static const List<Duration> _secretRetryDelays = [
    Duration(milliseconds: 150),
    Duration(milliseconds: 400),
  ];

  @override
  Future<PasscodeRecord> load() async {
    final prefs = await SharedPreferences.getInstance();
    // The FLAG is read first and from prefs, which cannot throw here: every
    // later decision needs to know whether a passcode exists at all, and a
    // secret read that throws must not be able to hide that fact (it used to
    // propagate out of load() and land in the provider's fail-OPEN branch —
    // a throwing Keystore silently unlocking the app).
    final flagged = prefs.getBool(enabledKey) ?? false;
    final autoLock =
        prefs.getInt(autoLockKey) ?? kPasscodeAutoLockDefaultSeconds;

    final secrets = await _readSecrets(prefs);

    // Unreadable and MISSING are the same verdict here — both mean no code
    // can be checked — but only because the read was retried first.
    final enabled =
        flagged && secrets.salt != null && secrets.verifier != null;
    final damaged = flagged && !enabled;

    return PasscodeRecord(
      enabled: enabled,
      credentialDamaged: damaged,
      mode: PasscodeMode.fromStorage(prefs.getString(modeKey)),
      salt: enabled ? secrets.salt : null,
      verifier: enabled ? secrets.verifier : null,
      iterations: secrets.iterations,
      autoLockSeconds: autoLock,
      lastActiveAtMs: prefs.getInt(lastActiveKey),
      failedAttempts: prefs.getInt(failedAttemptsKey) ?? 0,
      lockoutUntilMs: prefs.getInt(lockoutUntilKey),
    );
  }

  /// Reads salt/verifier/iterations, retrying the whole triple on any error.
  /// Returns nulls when storage still refuses — never throws, so the caller's
  /// flag-based verdict always gets taken.
  Future<({Uint8List? salt, Uint8List? verifier, int iterations})> _readSecrets(
    SharedPreferences prefs,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _secretRetryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_secretRetryDelays[attempt - 1]);
      }
      try {
        return (
          salt: _decode(await _readSecret(prefs, saltKey)),
          verifier: _decode(await _readSecret(prefs, verifierKey)),
          iterations:
              int.tryParse(await _readSecret(prefs, iterationsKey) ?? '') ??
                  kPasscodeKdfIterations,
        );
      } catch (e) {
        lastError = e;
      }
    }
    E2ePersistentDiag.record('PASSCODE_SECRET_UNREADABLE', {
      'errorType': lastError.runtimeType.toString(),
    });
    return (salt: null, verifier: null, iterations: kPasscodeKdfIterations);
  }

  @override
  Future<void> saveCredential({
    required PasscodeMode mode,
    required Uint8List salt,
    required Uint8List verifier,
    required int iterations,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Secret first: a failed secret write must not leave a flag claiming a
    // credential that does not exist.
    await _writeSecret(prefs, saltKey, base64Encode(salt));
    await _writeSecret(prefs, verifierKey, base64Encode(verifier));
    await _writeSecret(prefs, iterationsKey, '$iterations');
    await prefs.setString(modeKey, mode.storageValue);
    await prefs.setBool(enabledKey, true);
    await _resetAttempts(prefs);
  }

  @override
  Future<void> clearCredential() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, false);
    await _deleteSecret(prefs, saltKey);
    await _deleteSecret(prefs, verifierKey);
    await _deleteSecret(prefs, iterationsKey);
    await _resetAttempts(prefs);
  }

  @override
  Future<void> saveAutoLockSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(autoLockKey, seconds);
  }

  @override
  Future<void> saveLastActiveAt(int? epochMs) async {
    final prefs = await SharedPreferences.getInstance();
    if (epochMs == null) {
      await prefs.remove(lastActiveKey);
      return;
    }
    await prefs.setInt(lastActiveKey, epochMs);
  }

  @override
  Future<void> saveAttemptState({
    required int failedAttempts,
    required int? lockoutUntilMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(failedAttemptsKey, failedAttempts);
    if (lockoutUntilMs == null) {
      await prefs.remove(lockoutUntilKey);
      return;
    }
    await prefs.setInt(lockoutUntilKey, lockoutUntilMs);
  }

  Future<void> _resetAttempts(SharedPreferences prefs) async {
    await prefs.remove(failedAttemptsKey);
    await prefs.remove(lockoutUntilKey);
  }

  Future<String?> _readSecret(SharedPreferences prefs, String key) async {
    if (!_useSecure) return prefs.getString(key);
    return _secure.read(key);
  }

  Future<void> _writeSecret(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    if (!_useSecure) {
      await prefs.setString(key, value);
      return;
    }
    await _secure.write(key, value);
  }

  Future<void> _deleteSecret(SharedPreferences prefs, String key) async {
    if (!_useSecure) {
      await prefs.remove(key);
      return;
    }
    await _secure.delete(key);
  }

  Uint8List? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }
}
