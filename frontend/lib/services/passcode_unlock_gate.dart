import 'dart:async';

/// One-way valve between the passcode lock and the E2E boot.
///
/// Phase 2 makes the local key material undecryptable until the passcode is
/// entered, and the E2E stack does not wait for anything today: the gate hides
/// `MainShell` with `Offstage`, so `ConversationsScreen.initState` still runs,
/// the socket still connects, and `ConnectionProvider` still calls
/// `initializeE2E` — which reaches the first identity read while the vault is
/// still locked. Without a wait, that read would hit a locked store on every
/// boot and burn the session's single E2E init on a failure.
///
/// Deliberately NOT a provider: `EncryptionProvider` is constructed above the
/// widget tree that hosts the lock screen, and the openers it eventually
/// reaches are static functions behind conditional imports. A process-wide
/// valve is the only seam both ends can see. Mutable so a test can substitute
/// its own.
class PasscodeUnlockGate {
  static PasscodeUnlockGate instance = PasscodeUnlockGate();

  /// Open by default: a device with no passcode, or with wrapping off, must
  /// boot exactly as it did before Phase 2. Only a locked wrapped device
  /// closes it.
  bool _open = true;
  Completer<void>? _waiter;

  bool get isOpen => _open;

  /// Resolves immediately while open, otherwise when [open] is called. Never
  /// times out: the caller's alternative is to proceed against a locked store,
  /// which is the failure this exists to prevent. A user who never unlocks
  /// simply never initialises E2E — and cannot read anything anyway.
  Future<void> waitUntilOpen() {
    if (_open) return Future<void>.value();
    return (_waiter ??= Completer<void>()).future;
  }

  void open() {
    _open = true;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// Closes the valve for the NEXT boot-time read. It does not retract an E2E
  /// stack that is already up — the keys for an open store are already in RAM,
  /// and tearing that down mid-session would drop the socket and the active
  /// conversation (the same reason the lock screen uses `Offstage`). Cold boot
  /// is where the arithmetic guarantee lives; a mid-session re-lock is a UI
  /// barrier, and `frontend/CLAUDE.md` §10 says so out loud.
  void close() {
    _open = false;
  }
}
