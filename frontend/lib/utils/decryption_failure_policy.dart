import 'package:flutter/foundation.dart' show immutable;

/// Pure decision logic for what to do when decrypting an inbound E2E message
/// fails. Extracted from `_decryptMessageAsync` so the branching — the single
/// most dangerous code in the messaging layer, where a wrong choice deletes a
/// working Signal session — can be unit-tested in isolation.
///
/// This function holds NO provider state and performs NO side effects. The
/// caller classifies the raw exception into a [DecryptionFailureKind], passes
/// the orthogonal `hadIdentityReset` / `isHistory` flags, then *applies* the
/// returned [DecryptionFailureDecision] (logging, persistence, retry, content).

/// How the raw decrypt exception was classified (string-matched by the caller).
enum DecryptionFailureKind {
  /// `DuplicateMessageException` — the ratchet already consumed this key.
  duplicate,

  /// `Bad Mac` — message was encrypted for a different/old session key.
  badMac,

  /// `NoSessionException` — no Signal session with the peer yet.
  noSession,

  /// Anything else.
  unknown,
}

/// The rule that actually fired, after applying precedence. Drives diagnostics.
/// Note `identityReset` is not a [DecryptionFailureKind] — it is an orthogonal
/// override that supersedes [noSession]/[unknown] (but NOT [duplicate]/[badMac]).
enum DecryptionFailureRule { duplicate, badMac, identityReset, noSession, unknown }

/// The retry side effect the caller must perform.
enum DecryptionRetryAction {
  /// No retry — the session is valid (duplicate/badMac) or unrecoverable (reset).
  none,

  /// History pass: add the sender to the failed-peers set for the post-pass retry.
  markHistoryPeerForRetry,

  /// Live path: schedule the debounced live-decrypt retry for the sender.
  scheduleLiveRetry,
}

@immutable
class DecryptionFailureDecision {
  /// Which rule fired (for diagnostics / logging).
  final DecryptionFailureRule rule;

  /// Persist `[Decryption failed]` so future app starts skip re-attempting.
  /// Only duplicate/badMac persist; identity-reset and retryable kinds do not.
  final bool persistTerminalFailure;

  /// Set the in-memory message content to `[Decryption failed]` (terminal).
  /// When false, the message is returned unchanged (keeps its `[encrypted]`
  /// placeholder) so a later retry can still resolve it.
  final bool markContentFailed;

  /// The retry side effect to perform (or [DecryptionRetryAction.none]).
  final DecryptionRetryAction retryAction;

  /// Emit `requestSessionRebuild` to the peer (once per peer) WITHOUT touching
  /// any local state. Only the identity-reset rule sets this: our identity was
  /// just regenerated, so the peer's session targets keys that no longer exist —
  /// every message they send on it is dead until they re-key. Notifying them
  /// shrinks the loss window from "until we happen to reply" to "their next
  /// send". Their old session encrypts nothing we could ever read, so asking
  /// them to discard it destroys no recoverable data.
  final bool notifyPeerRebuild;

  const DecryptionFailureDecision({
    required this.rule,
    required this.persistTerminalFailure,
    required this.markContentFailed,
    required this.retryAction,
    this.notifyPeerRebuild = false,
  });
}

/// Decides the outcome of a failed inbound decrypt.
///
/// Precedence (mirrors the original if-chain exactly):
/// 1. `duplicate` / `badMac` → terminal + persist, no retry. These win even when
///    [hadIdentityReset] is true (the session is valid; the key was consumed or
///    the message was for an old key).
/// 2. `hadIdentityReset` → terminal, NOT persisted, no retry. All messages for the
///    old identity are unrecoverable; a fresh session will be built by the next
///    PreKey message.
/// 3. `noSession` → keep `[encrypted]` and retry (session rebuild).
/// 4. `unknown` → retry; on the live path also mark the row terminal immediately,
///    on the history path keep `[encrypted]` (marked failed later, post-retry).
DecryptionFailureDecision decideDecryptionFailure(
  DecryptionFailureKind kind, {
  required bool hadIdentityReset,
  required bool isHistory,
}) {
  switch (kind) {
    case DecryptionFailureKind.duplicate:
      return const DecryptionFailureDecision(
        rule: DecryptionFailureRule.duplicate,
        persistTerminalFailure: true,
        markContentFailed: true,
        retryAction: DecryptionRetryAction.none,
      );
    case DecryptionFailureKind.badMac:
      return const DecryptionFailureDecision(
        rule: DecryptionFailureRule.badMac,
        persistTerminalFailure: true,
        markContentFailed: true,
        retryAction: DecryptionRetryAction.none,
      );
    case DecryptionFailureKind.noSession:
    case DecryptionFailureKind.unknown:
      // Identity reset supersedes session-rebuild / retry handling.
      if (hadIdentityReset) {
        return const DecryptionFailureDecision(
          rule: DecryptionFailureRule.identityReset,
          persistTerminalFailure: false,
          markContentFailed: true,
          retryAction: DecryptionRetryAction.none,
          notifyPeerRebuild: true,
        );
      }
      final retryAction = isHistory
          ? DecryptionRetryAction.markHistoryPeerForRetry
          : DecryptionRetryAction.scheduleLiveRetry;
      if (kind == DecryptionFailureKind.noSession) {
        return DecryptionFailureDecision(
          rule: DecryptionFailureRule.noSession,
          persistTerminalFailure: false,
          markContentFailed: false, // keep [encrypted] until retry resolves it
          retryAction: retryAction,
        );
      }
      return DecryptionFailureDecision(
        rule: DecryptionFailureRule.unknown,
        persistTerminalFailure: false,
        // Live: mark failed now. History: keep [encrypted]; the post-retry pass
        // (`_markHistoryDecryptFailuresAfterRetry`) marks it failed if unresolved.
        markContentFailed: !isHistory,
        retryAction: retryAction,
      );
  }
}
