import 'package:flutter/foundation.dart';

import '../services/passcode_kdf.dart';
import '../services/passcode_store.dart';
import '../utils/e2e_persistent_diag.dart';
import '../utils/passcode_autolock.dart';

/// Where the app-level Passcode Lock stands right now.
enum PasscodeLockState {
  /// Before [PasscodeProvider.initialize] answers. Callers MUST treat this as
  /// "do not decide" — painting the chat list here would flash it for a frame
  /// on every cold start of a locked app.
  unknown,

  /// No passcode configured.
  disabled,

  /// Configured and satisfied for this foreground session.
  unlocked,

  /// Configured and demanding the code.
  locked,
}

enum PasscodeUnlockResult {
  ok,
  wrong,

  /// Too many wrong codes: refused without even hashing.
  temporarilyBlocked,

  /// The KDF itself is unavailable (no webcrypto native on this host). NOT a
  /// wrong code — it must never consume an attempt.
  unavailable,
}

/// Shortest accepted custom alphanumeric passcode.
const int kPasscodeMinAlphanumericLength = 4;

/// Ceiling on the boot-time credential read.
///
/// The gate covers the app until this resolves, so a storage layer that HANGS
/// (rather than throws) would otherwise leave a blank surface with no way in
/// and no error — the worst failure this feature can have.
///
/// **It MUST stay above `DevicePasscodeStore.secretReadBudget` (1.05 s) plus
/// the SharedPreferences read that precedes it.** If this fired first, the
/// catch below would take the no-readable-flag branch and a flagged-but-slow
/// store would silently unlock, re-opening the bypass `credentialDamaged`
/// closes. `test/services/passcode_store_test.dart` asserts the ordering.
const Duration kPasscodeStoreReadTimeout = Duration(milliseconds: 2500);

/// The app-level passcode: a device-local gate in front of the whole logged-in
/// shell, in the shape Zangi ships and the owner approved on 2026-09-03.
///
/// Scope is deliberately a GATE, not at-rest encryption: it does not wrap the
/// Signal identity, the content keys or the JWT. Wrapping those is a separate,
/// opt-in tier — `services/encryption/content_key_manager.dart` documents why
/// auth-binding key material is a way to LOSE history, and this repo has spent
/// three handoffs on identity loss. Consequences of the gate-only scope, stated
/// plainly: on Android the protected material is already Keystore-backed and
/// the window is `FLAG_SECURE`, so the gate is a real improvement; on web the
/// verifier and everything it guards sit in the same localStorage, so the gate
/// stops a person holding the phone and nothing more.
///
/// Forgetting the passcode is NOT survivable, by design (owner ruling
/// 2026-09-04): there is no password door, because a recovery path the
/// account password can walk through is not a lock. The only way past a
/// forgotten code is `services/local_data_eraser.dart` — destroy every local
/// store and sign in again — which is the model Telegram, Threema, Phantom
/// and Trust Wallet all ship.
class PasscodeProvider extends ChangeNotifier {
  PasscodeProvider({
    PasscodeStore? store,
    PasscodeKdf? kdf,
    int Function()? nowMs,
  }) : _store = store ?? DevicePasscodeStore(),
       _kdf = kdf ?? const Pbkdf2PasscodeKdf(),
       _now = nowMs ?? _wallClock;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final PasscodeStore _store;
  final PasscodeKdf _kdf;
  final int Function() _now;

  PasscodeRecord _record = PasscodeRecord.disabled;
  PasscodeLockState _state = PasscodeLockState.unknown;

  PasscodeLockState get state => _state;

  bool get isEnabled =>
      _state == PasscodeLockState.locked || _state == PasscodeLockState.unlocked;

  bool get isLocked => _state == PasscodeLockState.locked;

  PasscodeMode get mode => _record.mode;

  int get autoLockSeconds => _record.autoLockSeconds;

  int get failedAttempts => _record.failedAttempts;

  /// Time left on the brute-force cooldown, or null when attempts are allowed.
  Duration? get lockoutRemaining {
    final until = _record.lockoutUntilMs;
    if (until == null) return null;
    final remaining = until - _now();
    if (remaining <= 0) return null;
    return Duration(milliseconds: remaining);
  }

  /// Reads the stored credential and applies the auto-lock policy to this
  /// boot. A cold boot is treated exactly like a foreground return on purpose:
  /// on web a backgrounded PWA is FROZEN and then REPLACED by a hard reload
  /// (`utils/page_lifecycle_web.dart`), so "cold boot" and "came back" are the
  /// same event there, and a stricter rule would make the user's auto-lock
  /// choice meaningless on the primary platform.
  Future<void> initialize() async {
    try {
      _record = await _store.load().timeout(kPasscodeStoreReadTimeout);
    } catch (e) {
      // A store that THROWS or HANGS gives us no flag at all, and inventing a
      // lock for someone who may never have set one would let a storage
      // hiccup lock a user out of their own app. Holding `unknown` forever is
      // worse still: the gate would brick the app behind a blank surface with
      // no way in. So: no readable flag ⇒ no passcode, recorded loudly.
      E2ePersistentDiag.record('PASSCODE_STORE_UNREADABLE', {
        'errorType': e.runtimeType.toString(),
      });
      _record = PasscodeRecord.disabled;
      _setState(PasscodeLockState.disabled);
      return;
    }
    if (_record.credentialDamaged) {
      // Opposite polarity, deliberately: the flag READ TRUE, so a passcode
      // exists and its verifier is what we cannot read. Resolving that to
      // "unlocked" is the error-as-absence inversion that `AuthTokenStore`
      // was hardened against — a wiped or tampered Keystore entry would
      // silently open the app. Fail CLOSED; the lock screen's recovery door
      // (logout, keys intact) is the way through, and every code entry
      // reports `unavailable` rather than "wrong".
      E2ePersistentDiag.record('PASSCODE_CREDENTIAL_DAMAGED', const {});
      _setState(PasscodeLockState.locked);
      return;
    }
    if (!_record.enabled) {
      _setState(PasscodeLockState.disabled);
      return;
    }
    final lock = shouldLockOnForeground(
      enabled: true,
      lastActiveAtMs: _record.lastActiveAtMs,
      nowMs: _now(),
      autoLockSeconds: _record.autoLockSeconds,
    );
    _setState(lock ? PasscodeLockState.locked : PasscodeLockState.unlocked);
  }

  /// Turns the lock on. Returns false — changing nothing — when the code does
  /// not fit its mode or the KDF is unavailable.
  Future<bool> enable({
    required String passcode,
    required PasscodeMode mode,
  }) async {
    if (!isValidPasscode(passcode, mode)) return false;
    final salt = generatePasscodeSalt();
    final verifier = await _derive(passcode, salt, kPasscodeKdfIterations);
    if (verifier == null) return false;

    await _store.saveCredential(
      mode: mode,
      salt: salt,
      verifier: verifier,
      iterations: kPasscodeKdfIterations,
    );
    _record = await _store.load();
    _setState(PasscodeLockState.unlocked);
    return true;
  }

  /// Turns the lock off. Requires the current code.
  Future<bool> disable({required String passcode}) async {
    if (!isEnabled) return false;
    if (await _matches(passcode) != true) return false;
    await _store.clearCredential();
    _record = await _store.load();
    _setState(PasscodeLockState.disabled);
    return true;
  }

  /// Checks a code without changing any state. Used by the settings screens
  /// to gate a change or a disable behind the CURRENT passcode. Returns false
  /// for a wrong code and for an unavailable KDF alike — the caller's next
  /// step is the same either way, and neither may reveal anything more.
  Future<bool> verifyCurrent(String passcode) async {
    if (!isEnabled) return false;
    return await _matches(passcode) ?? false;
  }

  /// Replaces the credential (and possibly the mode). Requires the old code.
  Future<bool> change({
    required String current,
    required String next,
    required PasscodeMode mode,
  }) async {
    if (!isEnabled) return false;
    if (!isValidPasscode(next, mode)) return false;
    if (await _matches(current) != true) return false;

    final salt = generatePasscodeSalt();
    final verifier = await _derive(next, salt, kPasscodeKdfIterations);
    if (verifier == null) return false;
    await _store.saveCredential(
      mode: mode,
      salt: salt,
      verifier: verifier,
      iterations: kPasscodeKdfIterations,
    );
    _record = await _store.load();
    _setState(PasscodeLockState.unlocked);
    return true;
  }

  Future<PasscodeUnlockResult> unlock(String passcode) async {
    if (!isEnabled) return PasscodeUnlockResult.unavailable;
    if (lockoutRemaining != null) {
      return PasscodeUnlockResult.temporarilyBlocked;
    }

    final matched = await _matches(passcode);
    if (matched == null) return PasscodeUnlockResult.unavailable;

    if (matched) {
      if (_record.failedAttempts != 0 || _record.lockoutUntilMs != null) {
        await _store.saveAttemptState(failedAttempts: 0, lockoutUntilMs: null);
        _record = await _store.load();
      }
      _setState(PasscodeLockState.unlocked);
      return PasscodeUnlockResult.ok;
    }

    final failed = _record.failedAttempts + 1;
    final backoff = passcodeBackoffFor(failed);
    await _store.saveAttemptState(
      failedAttempts: failed,
      lockoutUntilMs: backoff == Duration.zero
          ? null
          : _now() + backoff.inMilliseconds,
    );
    _record = await _store.load();
    notifyListeners();
    return PasscodeUnlockResult.wrong;
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    if (!kPasscodeAutoLockChoices.contains(seconds)) return;
    if (seconds == _record.autoLockSeconds) return;
    await _store.saveAutoLockSeconds(seconds);
    _record = await _store.load();
    notifyListeners();
  }

  /// Demand the code now (the Chats-header padlock).
  void lockNow() {
    if (_state != PasscodeLockState.unlocked) return;
    _setState(PasscodeLockState.locked);
  }

  /// The app left the foreground: stamp the clock, and lock immediately when
  /// the user chose the immediate setting.
  ///
  /// The stamp is written on the way OUT because that is the only moment the
  /// away-time can start being measured, and because on web the process may
  /// never run code again (frozen page replaced, or iOS killing the PWA).
  Future<void> noteBackgrounded() async {
    if (!isEnabled) return;
    await _store.saveLastActiveAt(_now());
    _record = await _store.load();
    if (_record.autoLockSeconds <= 0) {
      _setState(PasscodeLockState.locked);
      return;
    }
    notifyListeners();
  }

  /// The app came back to the foreground.
  Future<void> evaluateOnForeground() async {
    if (!isEnabled) return;
    if (_state == PasscodeLockState.locked) return;
    // Re-read: another PWA engine on the same origin may have moved the stamp.
    _record = await _store.load();
    final lock = shouldLockOnForeground(
      enabled: true,
      lastActiveAtMs: _record.lastActiveAtMs,
      nowMs: _now(),
      autoLockSeconds: _record.autoLockSeconds,
    );
    if (lock) _setState(PasscodeLockState.locked);
  }

  Future<bool?> _matches(String passcode) async {
    final salt = _record.salt;
    final verifier = _record.verifier;
    if (salt == null || verifier == null) return null;
    final candidate = await _derive(passcode, salt, _record.iterations);
    if (candidate == null) return null;
    return constantTimeBytesEqual(candidate, verifier);
  }

  Future<Uint8List?> _derive(String passcode, Uint8List salt, int iterations) {
    return _kdf
        .derive(passcode: passcode, salt: salt, iterations: iterations)
        .then<Uint8List?>((v) => v)
        // A KDF failure must be a reported, recoverable state — never a
        // silent "wrong code", which would burn attempts and, on the settings
        // screens, look like the user's own code stopped working.
        .onError<Object>((_, _) => null);
  }

  void _setState(PasscodeLockState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }
}

/// Whether [passcode] is acceptable for [mode]: exact length and digits only
/// for the numeric modes, at least [kPasscodeMinAlphanumericLength] characters
/// for a custom one.
bool isValidPasscode(String passcode, PasscodeMode mode) {
  final fixed = mode.fixedLength;
  if (fixed != null) {
    if (passcode.length != fixed) return false;
    return RegExp(r'^\d+$').hasMatch(passcode);
  }
  return passcode.trim().length >= kPasscodeMinAlphanumericLength;
}
