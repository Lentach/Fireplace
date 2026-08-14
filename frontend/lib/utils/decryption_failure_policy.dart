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

  /// `InvalidKeyIdException` — the one-time (or signed) pre-key this
  /// PreKeySignalMessage was built on is no longer in our store. The private
  /// half is gone for good: Signal deletes a one-time pre-key the moment it
  /// completes an X3DH, and the server marks it used when it serves it. So
  /// this ciphertext is undecryptable FOREVER — nothing about it is transient.
  missingPreKey,

  /// `NoSessionException` — no Signal session with the peer yet.
  noSession,

  /// Anything else.
  unknown,
}

/// The rule that actually fired, after applying precedence. Drives diagnostics.
/// Note `identityReset` is not a [DecryptionFailureKind] — it is an orthogonal
/// override that supersedes [noSession]/[unknown] (but NOT [duplicate]/[badMac]).
enum DecryptionFailureRule {
  duplicate,
  badMac,
  missingPreKey,
  identityReset,
  noSession,
  unknown,
}

/// The retry side effect the caller must perform.
enum DecryptionRetryAction {
  /// No local retry — the row is terminal or unrecoverable.
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
  /// Only badMac/missingPreKey persist — the two provably permanent dead ends.
  /// Identity-reset and retryable kinds do not.
  final bool persistTerminalFailure;

  /// Set the in-memory message content to `[Decryption failed]` (terminal).
  /// When false, the message is returned unchanged (keeps its `[encrypted]`
  /// placeholder) so a later retry can still resolve it.
  final bool markContentFailed;

  /// The retry side effect to perform (or [DecryptionRetryAction.none]).
  final DecryptionRetryAction retryAction;

  /// Emit `requestSessionRebuild` to the peer WITHOUT touching any local state.
  /// Bad-MAC sends indicate their sender ratchet is stale; identity-reset sends
  /// target keys we no longer have; a missing pre-key means their whole session
  /// was built on a key we cannot complete, so every later message on it would
  /// fail too. In all three cases their next send must use a fresh PreKey
  /// message.
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
/// 1. `badMac` → terminal + persist, no retry, and asks the peer to re-key
///    (repeated Bad-MAC type-2 messages mean their sending ratchet is stale for
///    our current session). `duplicate` → terminal IN MEMORY only, NOT persisted:
///    the ratchet key is already consumed, so the plaintext is only recoverable
///    from the durable decrypted-content cache; persisting `[Decryption failed]`
///    would poison that cache and make a merely-transiently-unreadable (or
///    late-written) plaintext unrecoverable forever. Both win even when
///    [hadIdentityReset] is true. `duplicate` never asks the peer to re-key.
/// 1b. `missingPreKey` → terminal + persist, no retry, asks the peer to re-key.
///    Same tier as `badMac` and for the same reason: the referenced pre-key is
///    unrecoverable, so a retry can only re-fail. It MUST persist — while this
///    fell through to `unknown` (persist:false) the row re-failed on every
///    history pass and every boot, and each live re-fail scheduled a retry that
///    ended in `SESSION_RESET`, burning one of the peer's OTP fetches and
///    forcing another re-key. That is the observed 2026-08-14 loop (msg 20277,
///    `InvalidKeyIdException - No pre-key found for id: 0`).
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
      // Ratchet already consumed this key; the caller already tried the cache,
      // the in-memory row, and the persisted plaintext before reaching here.
      // Mark failed IN MEMORY (so this session's history pass doesn't loop on
      // it) but DO NOT persist: a persisted `[Decryption failed]` poisons the
      // durable cache so a plaintext row that was only transiently unreadable
      // (silent write failure, reconnect churn, late write) could never be
      // restored. With persist=false the next launch re-reads the durable cache
      // and RECOVERS the message when its plaintext is present, falling back to
      // failed only when it is genuinely lost. Safe: duplicate never triggers a
      // session reset (notifyPeerRebuild stays false), so re-attempting on a
      // later launch cannot reintroduce the Bad-MAC reset loop.
      return const DecryptionFailureDecision(
        rule: DecryptionFailureRule.duplicate,
        persistTerminalFailure: false,
        markContentFailed: true,
        retryAction: DecryptionRetryAction.none,
      );
    case DecryptionFailureKind.badMac:
      return const DecryptionFailureDecision(
        rule: DecryptionFailureRule.badMac,
        persistTerminalFailure: true,
        markContentFailed: true,
        retryAction: DecryptionRetryAction.none,
        notifyPeerRebuild: true,
      );
    case DecryptionFailureKind.missingPreKey:
      // Deliberately ABOVE the identity-reset override, like badMac: whether or
      // not our identity was just regenerated, this specific ciphertext is
      // dead, and persisting that fact is what stops the cross-boot re-fail
      // loop. Peer notify is what actually recovers the CONVERSATION — their
      // session is pinned to a pre-key we no longer hold.
      return const DecryptionFailureDecision(
        rule: DecryptionFailureRule.missingPreKey,
        persistTerminalFailure: true,
        markContentFailed: true,
        retryAction: DecryptionRetryAction.none,
        notifyPeerRebuild: true,
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
