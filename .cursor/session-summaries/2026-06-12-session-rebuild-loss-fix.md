# E2E regression round 2: lossful send-side rebuild + keyed-media reset loop + exactly-once send

**Date:** 2026-06-12

## What was done

Root-caused the post-0.0.47 receiver-side `[Decryption failed]` log (LOG B: conv 87, peer 58, msg 8489) and fixed the three remaining session-destroying paths the 06-10 fix had left behind. Verified every claim against the installed `libsignal_protocol_dart 0.7.4` source.

**LOG B mechanism (fully explained):**
1. **Eternal "unresolved" rows:** restored keyed-media rows (received voice/image) keep `content == '[encrypted]'` BY DESIGN (their decrypted payload is `mediaKey`/`mediaIv`, 0.0.43 fix) — but four predicates treated `displayAsEncryptedPlaceholder` alone as "still undecrypted": the `peersNeedingRetry` scan, `_recoverUnresolvedEncryptedInbound`, `_conversationHasUndecryptedInbound` (the 900ms retry gate), and `_pruneLiveDecryptFailedPeers`. Any chat with received media re-armed the reset machinery on EVERY history pass → the `SESSION_RESET{historyRetry}` repeats at 01:49:57/01:53:16×3.
2. **Surviving force-rebuild mark:** `_requestSessionRebuildForPeer` still called `markSessionRebuild` (our OWN session). The retry loop skips usable rows, so its success-branch never cleared the mark → `SESSION_ENSURE{hasSession:true, needsRebuild:true}` at the next send.
3a. **Orphaned-delete sub-path (confirmed by a second pre-fix capture, user 37 / peer 49 / msg 8592):** pre-fix `ensureSession` deleted BEFORE the bundle fetch, so a fetch timeout/failure left NO session at all (deleted, never rebuilt) — seen as `ctype:2 + hasSession:false` at next app start with `needsKeyUpload:false` (identity intact ⇒ not a storage wipe ⇒ code-driven delete). Fix removes this path too: no delete ⇒ failed rebuild fetch leaves the old session untouched. Same capture also showed the placeholder-row quirk *accidentally* clearing the rebuild mark (TEXT rows get re-attempted → "success" branch) — confirming Log B's mark survived precisely because keyed-media rows are skipped.
3. **The lossful delete:** `ensureSession`'s rebuild did `deleteSession` before `buildSession` — wiping the current AND all 40 archived ratchet states (`SessionRecord.archivedStatesMaxLength = 40`, `session_record.dart:28`). `processPreKeyBundle` archives the current state ITSELF (`session_builder.dart:139`) and persists atomically via one `storeSession` (`:160`), so the delete was pure destruction. Peer 58's in-flight whisper (ctype **2** — `whisperType=2`, not 1!) then had no matching state → `InvalidMessageException('No valid sessions. [Bad Mac!]')` → terminal loss (msg 8489). The integration test reproduces this byte-for-byte.

**Fixes (frontend/lib):**
- `encryption_provider.dart` — `ensureSession` rebuild builds OVER the record (no delete); logs `SESSION_ARCHIVED_FOR_REBUILD`.
- `messaging_provider.decrypt.dart` — `_requestSessionRebuildForPeer`: no `markSessionRebuild` (only inbound `sessionRebuildNeeded` may force-rebuild our session); once-per-peer dedupe via `_rebuildRequestedPeers` (cleared on a successful decrypt from that peer, kept across reconnects → kills the loop); new `_isUnresolvedEncryptedInbound` (placeholder AND `!_hasUsableDecryptedContent`) used by all four predicates; ctype doc fixed (2=Signal).
- `messaging_provider.send.dart` — exactly-once emit per tempId (`_emittedSendTempIds` latch before encrypt → duplicate logs `SEND_DUPLICATE_BLOCKED`, no ratchet advance; released by `_markMessageFailed`/`markSendingMessagesFailed` so user retry works; cleared on connect); `SEND_START`/`SEND_EMIT` log `tempId`.
- `messaging_provider.dart` — the two new sets, lifecycle wiring.

**LOG A verdicts:** (a) duplicate sends — no multiplier exists for one tempId in current source (every UI path is cleared-text/status-guarded); the 4×-same-length bursts are most plausibly rapid distinct sends (PING spam matches the constant 114-char ciphertext); tempId now in send logs makes a fresh capture decisive, and the latch makes the bug class impossible regardless. (b) `E2E_KEYS_REUPLOADED` — harmless by construction: `getKeyBundleForReupload` re-reads the SAME stored identity+signedPreKey(0); backend `upsertKeyBundle` is an idempotent upsert on `userId`, OTPs untouched. No rotation, no session invalidation.

## Key files
- `frontend/lib/providers/encryption_provider.dart`, `frontend/lib/providers/messaging_provider.dart`
- `frontend/lib/providers/messaging/messaging_provider.{decrypt,send}.dart`
- `frontend/test/providers/encryption_provider_session_rebuild_test.dart` (NEW — real two-party libsignal)
- `frontend/test/providers/messaging_provider_race_test.dart` (+3 tests, cascade test hardened)
- `CLAUDE.md` (decrypt-ordering invariants; ctype 3=PreKey/2=Signal), `frontend/pubspec.yaml` 0.0.53

## Verification
- Fail-before/pass-after (lib stashed): integration test fails with the EXACT prod exception `No valid sessions. [InvalidMessageException - Bad Mac!]`; cascade 2 emits→1; duplicate-send 2 emits→1; keyed-media test emits a rebuild request pre-fix → silence post-fix.
- Full frontend suite **368 green**; `flutter analyze` **zero issues**.
- libsignal 0.7.4 facts verified in pub-cache source: `whisperType=2/prekeyType=3` (`protocol/ciphertext_message.dart`); `processPreKeyBundle` archives current state (`session_builder.dart:76,139`) + single `storeSession` (`:160`); `decryptFromSignal` iterates `previousSessionStates` then throws `No valid sessions` (`session_cipher.dart:157-186`); 40-state archive cap (`state/session_record.dart:28`). Specs: Double Ratchet §2.6 (out-of-order/skipped keys), Sesame (session mgmt) — signal.org/docs.

## Notes for next session
- **Deploy 0.0.53** (flutter clean, gitCommit check, PWA cache-bust) then capture sender↔receiver logs: expect NO `SESSION_DELETED_FOR_REBUILD` ever (event removed; `SESSION_ARCHIVED_FOR_REBUILD` may appear and is lossless), `SESSION_RESET` at most once per peer between successful decrypts (`SESSION_RESET_SKIPPED{alreadyRequested}` otherwise), media-only chats fully silent on the reset path, and `SEND_EMIT` tempIds unique. In-flight messages across a rebuild must now decrypt (the 8489 class).
- Mixed versions: pre-0.0.53 peers still delete-on-rebuild locally; our once-per-peer request dedupe sharply limits how often we trigger that. Full settling needs both sides updated.
- Residual quirk (pre-existing, unfixed): `_retryDecryptForPeers` treats a returned-unchanged placeholder as success (`!= failed` check) and clears `_liveDecryptFailedPeers`/`clearSessionRebuild` — now harmless (nothing destructive downstream) but worth tightening someday.
- Rebuild-request delivery is best-effort and ONLINE-ONLY (`chat-key-exchange.service.ts` emits `sessionRebuildNeeded` to the target socket only if connected; nothing queued). With the once-per-peer dedupe, a dropped emit (offline peer > socket drop) is not re-issued mid-session — healed by us replying (our PreKey msg re-keys the peer anyway), a decrypt success (clears the latch), or app restart. If this edge ever matters, fix it server-side (persist pending rebuild flags, deliver on next connect) — NOT by client re-emission (that was the loop).
- Messages already Bad-MAC'd before this fix (incl. 8489) are unrecoverable — keys were destroyed at delete time.
