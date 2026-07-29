# HANDOFF — P0 INCIDENT: today's received messages flip to "[Decryption failed]" after app reopen (machinery from 0.0.136; live frontend is 0.0.137)

**Date:** 2026-07-29, written immediately after the owner's report. Fresh agent: read this FIRST, then root `CLAUDE.md`, `frontend/CLAUDE.md` §5, and `2026-07-28-session-instant-deletion-hardening.md`. Diagnosis runbook: `docs/runbooks/e2e-decryption-failed.md`.

## Symptom (owner's report, verbatim facts)

- All messages RECEIVED today render normally when they arrive.
- After closing and reopening the app, ALL of today's received messages show `[Decryption failed]`.
- Older history is apparently intact. App is unusable for the owner.
- Started after the 0.0.136 release went live (2026-07-28 ~23:45 UTC). The frontend has since moved to `0.0.137 / 53b2610` (paint-only change) — the owner's Settings footer will read 0.0.137, and it carries the same destruction machinery.

## Why this is a data-destruction emergency, not a display bug

The persisted plaintext record is the ONLY copy of a received message: the server holds ciphertext whose Double Ratchet key was consumed at first decrypt, so a destroyed record can NEVER be re-decrypted (`DuplicateMessage` → terminal `[Decryption failed]`). 0.0.136 added machinery that DESTROYS those records on a 1-minute in-session timer (`ConnectionProvider._startPlaintextSweepTimer`) plus at every socketReady (sweep, backlog drain, server reconciliation). If any of those rules misfires, every minute the client runs destroys more messages, irreversibly.

The symptom fingerprint matches a false destroy exactly: arrival looks fine (plaintext in RAM + on disk), some rule destroys the DISK record while the RAM copy keeps the UI alive, reopen re-serves history as `[encrypted]`, the disk record is gone, live re-decrypt of consumed ciphertext fails terminally.

## STEP 0 — stop the bleeding BEFORE diagnosing (every minute costs messages)

1. **Roll back the FRONTEND to 0.0.134** (`a00ab0f`, the last frontend WITHOUT purge/sweep/reconcile — note this also steps back over 0.0.137's paint-only send button, which is fine). All destruction logic is client-side; the backend can stay at 0.0.136 (its new events are additive; an old client simply never emits them).
   - On the PC: `git -C C:/Users/Lentach/Desktop/fireplace worktree add ../fireplace-rollback a00ab0f` then run `deploy-web.ps1` from that worktree (runbook "Branch testing before merge" flow — the deploy verifies the served bundle sha, expect `a00ab0f`).
   - Tell the owner: fully close + reopen the PWA. **NEVER uninstall, NEVER clear site data** — that destroys the Signal keys and ALL remaining history.
2. **Before the owner reopens anything else**, have him open Privacy & Safety → hacker-mode diag panel and COPY BOTH LOGS OUT (`E2ePersistentDiag` survives restarts, capped 80 — it may already be rotating evidence out). This is the primary evidence; get it before more entries push it out.

## Evidence to pull (in order)

1. **Owner's `E2ePersistentDiag` dump.** The fingerprint that names the guilty rule:
   - `PLAINTEXT_RECONCILED` with a large purge count → server reconciliation destroyed them (`getServedMessageIds` answered without ids it still serves).
   - `PURGE_BACKLOG_DRAINED` with large/repeating `owed` → backlog re-purge loop (`resolvePurged` failing to clear, e.g. cross-context lock issue).
   - Neither of the above but records still gone → the EXPIRY SWEEP (`sweepDestroyablePlaintext`) — it logs nothing on success, which is itself a diagnostic gap. `DECRYPT_DECISION` entries for today's ids confirm the terminal re-decrypt failures.
2. **VM backend logs** around the incident window: `cd ~/fireplace && docker compose -f docker-compose.prod.yml logs --since 24h backend | grep -i "served\|expir"` — how many `getServedMessageIds` requests, any errors from `findServedMessageIds`.
3. **DB ground truth** for a few affected message ids: do the rows still exist and what are `expiresAt` / `disappearAfterSeconds` / `hiddenByUserIds`? (`docker compose -f docker-compose.prod.yml exec db psql -U postgres -d chatdb` — quote camelCase columns.) Rows STILL PRESENT server-side while the client destroyed plaintext = client-side false destroy, proven.

## Ranked hypotheses (verify with a local repro, NOT in prod)

**H1 — expiry-deadline stamp bug (units or timezone) in the NEW record metadata. Best fit.**
Only records written by 0.0.136 code carry the `_expiresAt`/`_createdAt`/`_disappearAfter` stamps that make them ELIGIBLE for the expiry rule; pre-0.0.136 records have no stamps and only age via the 30-day retention epoch — which precisely explains "today's messages die, old history survives."
Check, in `frontend/lib/services/encryption_service.dart`:
- the stamp WRITE sites in `saveDecryptedContent` (and `stampRecordExpiry` ~:1176, re-stamped from `messageDelivered` at `messaging_provider.events.dart:176-215`): are values UTC **milliseconds** everywhere?
- `_recordExpiryDeadlineMs` + `destroyableMessageIds` (~:1237): a seconds-vs-milliseconds mix reads a today-stamp as 1970 → destroyed on the first sweep tick. A naive (no `Z`) ISO parse (`DateTime.parse` yields LOCAL time; owner is UTC+2 Warsaw) shifts deadlines 2h early — fatal for short disappearing timers, and blows through the 5-min `kExpiryPurgeGrace`.
- `messageExpiryDeadline` fallback (`message_expiry.dart:39`): a message with `disappearAfterSeconds` but null `expiresAt` gets `createdAt + 86400s` — check what `_createdAt` actually holds on real records.
Repro: unit test that saves a record shaped like a real received message from a timer-enabled conversation, runs `destroyableMessageIds(serverNow: <real now>)`, and asserts it is NOT flagged. If it IS flagged, you have the bug in one step.

**H2 — server reconciliation false negative.** PR #106 (invitation rework, merged into the SAME release) changed friend/conversation backend paths. `findServedMessageIds` (`backend/src/messages/messages.service.ts`) must stay at least as permissive as the history read (root `CLAUDE.md` §7). If #106 changed participant/conversation semantics so the join misses rows for rebuilt conversations, the server omits ids it still serves → client destroys them. Would typically hit MORE than just today's messages, but #106 also touches conversation creation — new/rebuilt conversation rows could be exactly the mismatch. Check `PLAINTEXT_RECONCILED` counts first; falsify with test_e2e against a local backend.

**H3 — `messageDelivered` re-stamp poisoning.** Only today's messages received delivered/read events since the deploy; `stampRecordExpiry` writes `expiresAt` parsed at `messaging_provider.events.dart:179` (`DateTime.parse(expiresAtRaw)`). If the wire value parses local/short, today's records get a past deadline. Same repro as H1.

**H4 — backlog re-purge loop.** `enqueuePurge` before destroy, `resolvePurged` after; if resolve fails persistently, ids re-purge on every launch — but that only re-destroys already-destroyed ids, so it does not fit "worked at arrival" unless combined with H1-H3. Check `PURGE_BACKLOG_DRAINED` counts.

Note: the owner's conversations very likely have a disappearing timer set (read-based, `markConversationRead` stamps `expiresAt` server-side — `backend/CLAUDE.md` §7). That is what makes today's messages ELIGIBLE for expiry rules at all. Ask him which chats broke and whether they have timers; a broken chat with NO timer would kill H1/H3 and point hard at H2.

## What is and is not recoverable

- Destroyed received-message plaintext: **gone cryptographically.** Only social recovery (sender re-sends; the SENDER's own outgoing records are keyed by ciphertext and were likely NOT destroyed).
- Identity/session keys: untouched by all four hypotheses — future messaging works after the rollback.
- Do NOT run any "cleanup", "wipe", retention change, or reconcile experiment against the owner's device until the guilty rule is identified in a local repro.

## State of the world

- Prod NOW: frontend `0.0.137 / 53b2610` (PR #109, composer hex send — PAINT ONLY, carries all 0.0.136 machinery unchanged), backend `0.0.136 / 6fb36bf`. The destruction machinery went live in 0.0.136 (backend 23:42 UTC, web 23:45 UTC 2026-07-28, smoke 5/5 then). PRs #108 (e2e-safety) + #106 (invitation rework) shipped together in 0.0.136.
- Frontend rollback target is therefore still `a00ab0f` (0.0.134) — the last frontend with NO purge/sweep/reconcile. Rolling back also reverts the 0.0.137 send-button paint; irrelevant during the incident.
- Also on master since: Android release Phase 1 (keystore/signing, nothing distributed) — unrelated to this incident but explains recent commits. Correction recorded there that overrides older notes: the web at-rest store is localStorage + RAW SharedPreferences, NOT IndexedDB.
- All destruction machinery ships in #108's commits (`42603d2` purge, `4fa1ab7` reconcile, `d998408` in-session sweep timer); #106 changed the backend relationship/conversation paths the reconcile predicate depends on.
- Related incident already recorded in LATEST: the VM briefly ran the unmerged invitation branch (~2 min, `bde08b3`) before the real deploy — no migrations, believed harmless, but note it when reading backend logs from that window.
- Suites were green (backend 577/47, Flutter 1069+5, e2e-wire in CI) — whatever this is, the suites do not cover it; when you find it, add the failing test FIRST.

## Definition of done for the incident

1. Frontend rolled back, destruction stopped, owner messaging again.
2. Guilty rule identified with a fail-before test reproducing the false destroy.
3. Fix + test green, re-released with the fix, and the sweep/reconcile paths gain SUCCESS-side diagnostics (the expiry sweep currently destroys silently — that gap made this diagnosis harder than it needed to be).
4. Honest accounting to the owner of what was destroyed and that it cannot be restored.
