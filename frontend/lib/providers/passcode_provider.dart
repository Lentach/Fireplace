import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/encryption/content_key_manager.dart';
import '../services/encryption/content_key_wrap.dart';
import '../services/passcode_kdf.dart';
import '../services/passcode_store.dart';
import '../services/passcode_unlock_gate.dart';
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

/// Key families the passcode wrap covers: the payload keys that seal the
/// Signal rows and the decrypted-content rows. Deliberately NOT the sealed
/// rows themselves and NOT the SQLCipher DB key (native only) — see
/// `services/encryption/content_key_wrap.dart` for why encrypting a row's
/// cleartext envelope prefix would re-trigger the 0.1.10 identity loss.
const List<String> kPasscodeWrappedKeyPrefixes = <String>[
  ContentKeyManager.contentKeyPrefix,
  ContentKeyManager.sigKeyPrefix,
];

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
    ContentKeyWrap? vault,
    PasscodeUnlockGate? gate,
    bool? wrapKeys,
  }) : _store = store ?? DevicePasscodeStore(),
       _kdf = kdf ?? const Pbkdf2PasscodeKdf(),
       _now = nowMs ?? _wallClock,
       _vault = vault ?? ContentKeyWrap.instance,
       _gate = gate ?? PasscodeUnlockGate.instance,
       _wrapKeys = wrapKeys ?? kIsWeb;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final PasscodeStore _store;
  final PasscodeKdf _kdf;
  final int Function() _now;

  /// Phase 2: the passcode-derived wrap around the local content keys.
  final ContentKeyWrap _vault;

  /// Phase 2: holds the E2E boot until the vault is open.
  final PasscodeUnlockGate _gate;

  /// Whether enabling the passcode should also wrap the local key material.
  /// Web only by owner ruling (2026-09-04): on Android the same material is
  /// already Keystore-backed behind `FLAG_SECURE`, and wrapping it there would
  /// turn every Keystore fault into permanent history loss on the platform
  /// where a forgotten code is currently survivable. Injectable so the
  /// behaviour is testable off-web.
  final bool _wrapKeys;

  bool get wrapsKeys => _wrapKeys;

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
      // silently open the app. Fail CLOSED; the lock screen's erase action is
      // the way through, and every code entry reports `unavailable` rather
      // than "wrong".
      E2ePersistentDiag.record('PASSCODE_CREDENTIAL_DAMAGED', const {});
      await _closeGateIfWrapping();
      _setState(PasscodeLockState.locked);
      return;
    }
    if (!_record.enabled) {
      _gate.open();
      _setState(PasscodeLockState.disabled);
      return;
    }
    var lock = shouldLockOnForeground(
      enabled: true,
      lastActiveAtMs: _record.lastActiveAtMs,
      nowMs: _now(),
      autoLockSeconds: _record.autoLockSeconds,
    );
    // With wrapping on, the KEK lives only in RAM, so a process that starts
    // with a locked vault CANNOT read the key material no matter what the
    // auto-lock window says. Demanding the code is then not a policy choice
    // but arithmetic: without it there is nothing to show.
    if (!lock && await _vault.isWrappingOn() && _vault.isLocked) {
      lock = true;
    }
    if (lock) {
      await _closeGateIfWrapping();
    } else {
      _gate.open();
    }
    _setState(lock ? PasscodeLockState.locked : PasscodeLockState.unlocked);
  }

  /// Holds the E2E boot only when there is something it could not read: with
  /// wrapping off, a locked UI must never stall the encryption stack.
  Future<void> _closeGateIfWrapping() async {
    if (await _vault.isWrappingOn()) _gate.close();
  }

  /// Turns the lock on. Returns false — changing nothing — when the code does
  /// not fit its mode, when the mode is not allowed under wrapping, or when
  /// the KDF is unavailable.
  Future<bool> enable({
    required String passcode,
    required PasscodeMode mode,
  }) async {
    if (!isValidPasscode(passcode, mode)) return false;
    if (!_modeAllowed(mode)) return false;
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
    if (_wrapKeys) await _turnWrappingOn(passcode);
    _gate.open();
    _setState(PasscodeLockState.unlocked);
    return true;
  }

  /// Turns the lock off. Requires the current code.
  ///
  /// Unwrapping comes FIRST and must succeed: dropping the credential while
  /// keys are still wrapped would leave envelopes whose KEK can never be
  /// re-derived — unreadable history with no passcode to blame.
  Future<bool> disable({required String passcode}) async {
    if (!isEnabled) return false;
    if (await _matches(passcode) != true) return false;
    if (await _vault.isWrappingOn()) {
      if (_vault.isLocked && !await _openVault(passcode)) return false;
      if (!await _vault.unwrapAllKeys(kPasscodeWrappedKeyPrefixes)) {
        return false;
      }
      await _vault.disableWrapping();
    }
    await _store.clearCredential();
    _record = await _store.load();
    _gate.open();
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
    if (!_modeAllowed(mode)) return false;
    if (await _matches(current) != true) return false;

    final salt = generatePasscodeSalt();
    final verifier = await _derive(next, salt, kPasscodeKdfIterations);
    if (verifier == null) return false;

    // Re-wrap BEFORE the credential moves: if the rekey fails, the old code
    // still opens both the verifier and the vault, so the device stays
    // consistent rather than half-migrated.
    if (await _vault.isWrappingOn()) {
      final kekSalt = generatePasscodeSalt();
      final kek = await _derive(next, kekSalt, kPasscodeKdfIterations);
      if (kek == null) return false;
      final ok = await _vault.rekey(
        newKek: kek,
        newKekId: _newKekId(),
        iterations: kPasscodeKdfIterations,
        saltB64: base64Encode(kekSalt),
        prefixes: kPasscodeWrappedKeyPrefixes,
      );
      if (!ok) return false;
    }

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
      // The verifier said yes, but on a wrapped device the code must also
      // OPEN the vault, and a code that verifies while the KEK cannot be
      // rebuilt must not unlock the UI: the app would come up with every
      // local key unreadable and no explanation.
      if (!await _openVault(passcode)) {
        return PasscodeUnlockResult.unavailable;
      }
      if (_record.failedAttempts != 0 || _record.lockoutUntilMs != null) {
        await _store.saveAttemptState(failedAttempts: 0, lockoutUntilMs: null);
        _record = await _store.load();
      }
      _gate.open();
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
    _lock();
  }

  /// Locking drops the KEK, so the NEXT process cannot read the key material
  /// without the code. It deliberately does not tear down an E2E stack that
  /// is already up: the open store holds its keys in RAM, and unmounting it
  /// would drop the socket, the active conversation and any in-flight send
  /// (the same reason the gate uses `Offstage`). Cold boot is where the
  /// arithmetic guarantee lives; a mid-session re-lock is a UI barrier.
  void _lock() {
    _vault.lock();
    _gate.close();
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
      _lock();
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
    if (lock) _lock();
  }

  /// Whether [mode] may be used on this device.
  ///
  /// A 4-digit code is 10 000 candidates, and once it is the key rather than
  /// a verifier those candidates can be tried OFFLINE against the wrapped
  /// keys — the published Bitwarden PIN exploit is exactly this. So the shape
  /// stays available while the passcode is only a gate (owner ruling
  /// 2026-09-04) and is refused wherever wrapping is on.
  bool _modeAllowed(PasscodeMode mode) =>
      !(_wrapKeys && mode == PasscodeMode.digits4);

  /// Re-derives the KEK from [passcode] and opens the vault. True when there
  /// is nothing to open (wrapping off) or the vault is now open.
  ///
  /// Also finishes any interrupted migration: `wrapRawKeys` is idempotent, so
  /// every unlock is a resume point and a device interrupted mid-enable
  /// converges instead of staying half-wrapped.
  Future<bool> _openVault(String passcode) async {
    if (!await _vault.isWrappingOn()) return true;
    final meta = await _vault.readMeta();
    if (meta == null) return false;
    final kek = await _derive(passcode, meta.salt, meta.iterations);
    if (kek == null) return false;
    _vault.unlock(kek: kek, kekId: meta.kekId);
    await _vault.wrapRawKeys(kPasscodeWrappedKeyPrefixes);
    return true;
  }

  /// Turns wrapping on for a code that was just accepted. Best-effort by
  /// design: if it fails the user still has the Phase 1 gate, which is
  /// strictly better than refusing to set a passcode at all — and the failure
  /// is recorded rather than guessed at later.
  Future<void> _turnWrappingOn(String passcode) async {
    final kekSalt = generatePasscodeSalt();
    final kek = await _derive(passcode, kekSalt, kPasscodeKdfIterations);
    if (kek == null) {
      E2ePersistentDiag.record('PASSCODE_WRAP_ENABLE_FAILED', {
        'stage': 'derive',
      });
      return;
    }
    final on = await _vault.enableWrapping(
      kek: kek,
      kekId: _newKekId(),
      iterations: kPasscodeKdfIterations,
      saltB64: base64Encode(kekSalt),
    );
    if (!on) {
      E2ePersistentDiag.record('PASSCODE_WRAP_ENABLE_FAILED', {
        'stage': 'meta',
      });
      return;
    }
    final wrapped = await _vault.wrapRawKeys(kPasscodeWrappedKeyPrefixes);
    E2ePersistentDiag.record('PASSCODE_WRAP_ENABLED', {'keys': wrapped ?? -1});
  }

  String _newKekId() => 'kek${_now()}';

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
