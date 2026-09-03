/// Pure policy for the app-level Passcode Lock: given how long the app was
/// out of the foreground, must the passcode be demanded again?
///
/// Kept platform-free and pure for the same reason as
/// `frozen_page_reload_decision.dart`: on web the lock decision is re-taken
/// after a hard `location.reload()` (a backgrounded Android-Chrome PWA is
/// frozen after ~5 min and REPLACED on thaw), and on iOS the PWA process is
/// killed outright. There is therefore no in-RAM "was unlocked" fact to lean
/// on — the verdict must be derivable from a persisted timestamp alone, on
/// every platform, and that is exactly what this function is.
library;

/// Auto-lock delays offered in the UI, seconds. `0` = lock the instant the app
/// leaves the foreground.
const List<int> kPasscodeAutoLockChoices = <int>[0, 60, 300, 3600];

/// Owner ruling 2026-09-03: default one minute. Stricter than Telegram's
/// one-hour default, and tolerable because returning to the app is one code
/// entry, not a re-login.
const int kPasscodeAutoLockDefaultSeconds = 60;

/// Whether the lock screen must be shown when the app comes back to the
/// foreground (or boots).
///
/// [lastActiveAtMs] is the persisted wall-clock stamp written when the app was
/// last seen in the foreground; null means "no stamp on disk", which is the
/// cold-boot / cleared-storage shape.
///
/// Fail-closed on anything unclear — a null stamp and a backwards clock both
/// lock. Over-locking costs one code entry; under-locking hands the chat list
/// to whoever is holding the phone, which is the entire threat this feature
/// exists for.
bool shouldLockOnForeground({
  required bool enabled,
  required int? lastActiveAtMs,
  required int nowMs,
  required int autoLockSeconds,
}) {
  if (!enabled) return false;
  if (lastActiveAtMs == null) return true;
  if (autoLockSeconds <= 0) return true;
  final awayMs = nowMs - lastActiveAtMs;
  if (awayMs < 0) return true;
  return awayMs >= autoLockSeconds * 1000;
}

/// Wrong codes tolerated before the lock screen starts refusing attempts.
/// Below this, a fat-fingered PIN costs nothing.
const int kPasscodeAttemptsBeforeBackoff = 5;

/// Cooldown after [failedAttempts] consecutive wrong codes.
///
/// This is the ONLY brute-force resistance the app-level gate has, and it is
/// honest about being soft: the counter lives in the same storage as the
/// verifier, so on web anyone with devtools can reset it. It exists to stop
/// hand-typed guessing by someone holding the phone — the threat this
/// feature is actually for — not offline attack.
Duration passcodeBackoffFor(int failedAttempts) {
  if (failedAttempts < kPasscodeAttemptsBeforeBackoff) return Duration.zero;
  return switch (failedAttempts - kPasscodeAttemptsBeforeBackoff) {
    0 => const Duration(seconds: 30),
    1 => const Duration(minutes: 1),
    2 => const Duration(minutes: 5),
    _ => const Duration(minutes: 15),
  };
}
