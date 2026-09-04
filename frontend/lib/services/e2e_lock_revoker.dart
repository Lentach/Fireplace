import 'dart:async';

/// Process-wide seam through which a mid-session passcode re-lock tears the
/// LIVE E2E stack down, and an unlock brings it back.
///
/// Why a process-wide object rather than provider wiring, exactly as for
/// [PasscodeUnlockGate]: `EncryptionProvider` is constructed above the widget
/// tree that hosts the lock screen, the stores it eventually reaches are
/// static functions behind conditional imports, and `PasscodeProvider` must be
/// able to complete the teardown synchronously with the lock — not one frame
/// later through a listener. Mutable so a test can substitute its own.
///
/// Both directions are SERIALIZED against each other. A user who locks and
/// immediately unlocks must not have the restore overtake the teardown and
/// re-initialise E2E onto stores that are about to be revoked.
class E2eLockRevoker {
  static E2eLockRevoker instance = E2eLockRevoker();

  /// Drops every key and every plaintext the live E2E stack holds in RAM.
  /// Registered by [EncryptionProvider]; null before any provider exists (and
  /// in tests that never build one), in which case [revoke] is a no-op.
  Future<void> Function()? onRevoke;

  /// Brings E2E back after an unlock that did NOT restart the process.
  Future<void> Function()? onRestore;

  Future<void> _tail = Future<void>.value();

  /// True while a revoke/restore is queued or running — used by tests and by
  /// diagnostics; never by control flow, because the tail is the ordering
  /// guarantee, not this flag.
  bool get isBusy => _busy > 0;
  int _busy = 0;

  Future<void> revoke() => _serialize(onRevoke);

  Future<void> restore() => _serialize(onRestore);

  Future<void> _serialize(Future<void> Function()? action) {
    if (action == null) return Future<void>.value();
    _busy++;
    final next = _tail.then((_) => action()).whenComplete(() => _busy--);
    // The tail must not carry the error forward: one failed teardown must not
    // wedge every later lock/unlock. The failure still propagates to the
    // caller through the returned future.
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}
