# E2E decrypt regression: Bad-MAC → session-reset cascade root-caused and fixed

**Date:** 2026-06-10

## What was done

Root-caused and fixed the two classes of `[Decryption failed]` reports (mid-conversation losses + first-message-after-cache-clear), added field instrumentation, and pinned everything with regression tests.

**Class B (mid-conversation, msgs 7657/7658 / peer 37) — real code bug, three cooperating defects:**

1. **`_retryDecryptForPeers` deleted the local Signal session** (`deleteSessionWithPeer`) as "recovery" for inbound decrypt failures. Deleting the SessionRecord wipes the current AND archived ratchet states, so every message the peer had already encrypted with them becomes a permanent Bad-MAC loss — that IS the mid-conversation failure. The rebuild *request* alone is lossless (libsignal archives the old state when a PreKey message arrives). Introduced ≤05-28 (`09ec7ff` fixed the main-loop re-trigger but left the retry loop's delete).
2. **Sticky `_liveDecryptFailedPeers`**: a peer entered the set on one live failure and was only removed on a *successful* decrypt — but the rows being retried were terminal and could never succeed, so every later history pass (every reconnect, every notification-driven open) re-fired the reset machinery against a possibly-valid fresh session. Also the retry loop lacked the main loop's `[Decryption failed]` skip guard, and `_recoverUnresolvedEncryptedInbound` double-emitted `requestSessionRebuild` per pass.
3. **`_mergeHistorySnapshot` dropped local state for overlapping ids** (`!serverIds.contains(m.id)` exclusion, introduced `d6a851c` 05-17): every server snapshot replaced local rows wholesale, so `_mergeMessagePreferNewer` never ran for exactly the rows it was written for. Decrypted/terminal rows were resurrected as `[encrypted]` placeholders on every reconnect (normally re-healed from the decrypt cache — but non-persisted terminal rows re-armed the machinery each pass → the 20:14:54–:57 repeat in the prod log).

None of the 06-06 decomposition / 06-09 policy-extraction commits changed behavior (verified hunk-by-hunk: pre-split bodies byte-identical; policy extraction faithful to the old if-chain). The defects predate; frequency jumped because the new push deep-linking multiplies reconnect+history passes per day.

**Class A (first 1–3 messages after "cache clear") — confirmed state loss, not a code bug, handling improved:**
- In-app "Clear local message cache" deletes ONLY `e2e_<uid>_decrypted_*` plaintext (sessions/identity untouched) → can NOT cause Class A. The affected user must have done a browser site-data clear / PWA reinstall (or Safari storage eviction) — on web `DualStorage` is localStorage-only, so that wipes identity+sessions. Peer's old-session messages are then cryptographically unrecoverable (Signal has no key recovery) — correct response is graceful + observable.
- Improvement: `decideDecryptionFailure` identityReset rule now sets `notifyPeerRebuild` → emits `requestSessionRebuild` once per peer (no local state touched) so the peer re-keys on their NEXT send instead of after we happen to reply — shrinks the loss from "first 1–3" to typically "first 1".

**Fixes (frontend/lib):**
- `messaging/messaging_provider.decrypt.dart`: removed `deleteSessionWithPeer` from `_retryDecryptForPeers`; terminal-row skip in the retry loop; `_pruneLiveDecryptFailedPeers()` (after retry + after `_markHistoryDecryptFailuresAfterRetry`); deduped `_recoverUnresolvedEncryptedInbound` emits via `_historySessionRebuildRequested`; identity-reset peer notification (once per session via `_identityResetRebuildNotified` in core).
- `messaging/messaging_provider.history.dart`: `_mergeHistorySnapshot` pre-seeds ALL local rows so overlapping ids go through `_mergeMessagePreferNewer`.
- `utils/decryption_failure_policy.dart`: new `notifyPeerRebuild` field (true only for identityReset).
- `encryption_provider.dart`: `hasSessionWith()`; diag logs.

**Instrumentation (E2eDiagLog, ids/booleans only — no plaintext/keys):** `DECRYPT_START` += `ctype` (3=PreKey/1=Signal) + `hasSession`; new `DECRYPT_DECISION` (kind/rule/isHistory/idReset/persist/markFailed/retry/notifyPeer); `SESSION_RESET` += `trigger` (historyRetry/liveRetry/recoverUnresolved); new `SESSION_DELETE`, `LIVE_RETRY_PRUNED`, `IDENTITY_RESET_REBUILD_REQUESTED`, `CACHE_CLEAR` (scope+count).

## Key files
- `frontend/lib/providers/messaging/messaging_provider.decrypt.dart`
- `frontend/lib/providers/messaging/messaging_provider.history.dart`
- `frontend/lib/providers/messaging_provider.dart` (new `_identityResetRebuildNotified` field)
- `frontend/lib/providers/encryption_provider.dart`
- `frontend/lib/utils/decryption_failure_policy.dart`
- `frontend/test/providers/messaging_provider_race_test.dart` (2 new tests + 2 flipped pins + 2 fixture date fixes)
- `frontend/test/utils/decryption_failure_policy_test.dart`, `frontend/test/services/encryption_service_content_cache_test.dart`

## Verification
- New regression tests FAIL on pre-fix code (`git stash push -- frontend/lib` → 4 failures: 2 session deletes in the NoSession-cascade test, 1 delete each in the retry tests, 0 identity-reset notifications) and PASS with the fix.
- `cd frontend && flutter test` → **325 passed** (was 315 + new tests + existing notification tests).
- `flutter analyze` → only 1 pre-existing info in `main_shell_notification_nav_test.dart` (not from this change).
- Fixture note: two TTL tests used 2026-01-01 createdAt; once the merge actually preserves TTL, never-read disappearing rows >24h old correctly expire — fixtures moved to recent timestamps.

## Notes for next session
- **Deploy + field-verify:** bump PATCH, deploy, then capture E2eDiagLog from an affected device. Expect: `DECRYPT_DECISION` explains every failure; `SESSION_DELETE` never appears (that event only exists on the now-dead inbound path); `LIVE_RETRY_PRUNED` confirms the loop settles; Class-A devices show `E2E_INIT_DONE needsKeyUpload:true` (identity recreated) + `IDENTITY_RESET_REBUILD_REQUESTED`. **`SESSION_DELETED_FOR_REBUILD` MAY legitimately appear** — that's `ensureSession`'s atomic delete+rebuild at send time after a rebuild request; don't false-alarm on it.
- **Mixed-version caveat:** the fixed client stops *initiating* destruction, but an old-version peer still runs the deleting retry path + sticky set on their side — they can keep wiping their own sessions and spamming `requestSessionRebuild` until they update. Per-pair full settling requires BOTH participants on the fixed build; the fixed client degrades gracefully meanwhile (its `ensureSession` rebuilds are PreKey-driven and its inbound never deletes).
- `hasSessionWith` is now awaited per decrypt (`DECRYPT_START`): on web it's an in-memory SharedPreferences lookup after first load; on mobile a Keychain/Keystore read — negligible vs the ratchet decrypt, but it IS on the hot path now.
- One-line rename pending next time that file is touched: `_buildApp` local in `main_shell_notification_nav_test.dart` (pre-existing analyze info).
- **Residual (flagged, not fixed):** (1) live-noSession rows with no history pass can re-schedule the 800ms retry until a pass terminalizes them (bounded by prune, emits deduped); (2) `markSessionRebuild` from the rebuild-request path still forces OUR next send to delete+rebuild via `ensureSession` — lossless for inbound (peer re-keys via our PreKey msg) but burns OTPs if requests are frequent; (3) a truly corrupted-but-present local session (persistent Bad-MAC on NEW live messages) has no automatic recovery anymore by design — needs separate detection if it ever shows up; (4) `_retryDecryptForPeers` treats a returned-unchanged placeholder as "success" (`!= failed` check) and clears the peer from sets — harmless now, worth tightening someday.
- 7657/7658 (and any rows Bad-MAC'd during the cascade era) are permanently lost — keys were destroyed at delete time; no fix can recover them.
