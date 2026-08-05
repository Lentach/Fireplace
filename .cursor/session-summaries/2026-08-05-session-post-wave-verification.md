# Post-wave verification — the 08-03→08-05 change wave re-checked from source

**Date:** 2026-08-05 (evening)

Owner was AFK across the audit/remediation/sealing/Android wave and asked for an independent
"is this safe, what changed, what is left" pass. **No code was changed.** This is a verification
record: every claim in the 08-03→08-05 summaries was re-derived from source or from a command run
this session, by six parallel agents (2 reviewers, 4 scouts) plus direct checks.

## What was done

**Verdict: SAFE. Nothing reverted, nothing half-applied, no rollback needed.** One doc-wording
ambiguity fixed (below). Both reviewers returned `correct`; all four scouts returned SAFE or
SAFE-WITH-CAVEATS where the caveat is a known, documented, deliberate tradeoff.

- **Merge integrity, measured (this is what the owner actually feared).** For `41e2f0b`, `195d894`,
  `2db65d9`, `dc5bfb5` the merge result is byte-identical to the branch tip — **0 files differ**, so
  no branch hunk was dropped. The only two conflict resolutions in `eb84451..565d1d9` (`84737bc`,
  `7e0596a`) are **docs-only** (`LATEST.md`, the `CLAUDE.md` §3 test-count line). Zero deleted files,
  zero reverts in range.
- **Nine previously-shipped fixes re-confirmed present**, each at a path:line: expiry-stamp
  destruction fix (`encryption_service.dart:2078-2081`), `detachReplies` in all three paths
  (`messages.service.ts:694,:814`, `message-cleanup.service.ts:94-99`), terminal-duplicate
  retirement + `DECRYPT_DECISION` dedupe, FLAG_SECURE (`MainActivity.kt:19-20`), storage-sets
  inspector, B2a behind `ContentKv`, `storage.persist()` at `main.dart:86`, the `991a6b2`
  `profilePhotos` guard, media→detach→row ordering.
- **BE-007 carve-out holds** — the one place a mistake would silently eat messages.
  `newMessage`/`messageEdited` still `emitToNewestTab` (`chat-message.service.ts:131,:601`); every
  other emit is room-wide; push suppression reads the SAME socket (`:621`). Grep found no
  ciphertext-bearing emit that went room-wide. `sessionRebuildNeeded` did go room-wide but carries
  only `{fromUserId}`.
- **Live backend is wire-compatible with the 0.1.8 field client**: no event renamed or removed; the
  four tightened DTOs only reject values that were never valid (`@IsInt @IsPositive` on ids).
- **Frontend delta safe to deploy once the canary clears.** The rollback claim was verified against
  `c01317c`'s own source, not the summary: old `SecureIdentityKeyStore.loadFromStorage` hits an
  unguarded `jsonDecode` on an `fpsig1:` value and **throws before** the `absent → _generateKeys()`
  branch — so a rollback breaks web decryption until roll-forward but **destroys nothing**.
- **Doc fix (source won).** `LATEST.md` read "20 s ack bound on accept/decline/**send**". There is no
  message-send ack timer: `_kInvitationAckTimeout` (`friends_provider.dart:38`) covers invitation
  accept/decline/send only, and message send is fire-and-forget **on purpose** (FE-024 — failing a
  send the server received releases the exactly-once latch and invites a duplicate). Wording
  clarified so a future agent does not "fix" the absence and re-open that hazard.

## Key files

- Reviewed (unchanged): `backend/src/chat/**`, `backend/src/messages/messages.service.ts`,
  `backend/src/chat/utils/user-room.ts`, `backend/migrations/0011_*.sql`,
  `frontend/lib/services/api_service.dart`, `frontend/lib/services/encryption/**`,
  `frontend/lib/providers/messaging/**`.
- Edited: `.cursor/session-summaries/LATEST.md` (new entry, oldest entry retired to its dated file,
  ack-wording clarified), this file.

## Verification

Everything below was run this session, on clean `master` `565d1d9`:

| Check | Result |
|---|---|
| `cd backend && npm test` | **670 passed / 49 suites** — matches `CLAUDE.md` §3 exactly |
| `cd frontend && flutter analyze --no-fatal-infos` | **No issues found** (65 s) |
| `cd frontend && flutter test` | **1247 passed / 10 skipped** (176 s) — matches §3 exactly |
| both count verifiers | OK / OK |
| `node scripts/lint-ratchet.mjs` | PASS, held at baseline 912 |
| `gh run list --branch master` | last 6 runs all `success` |
| `gh pr list --state open` / dependabot alerts | 0 open PRs / **0 open alerts** |
| `scripts/smoke/post-deploy-smoke.mjs` | 4/5 — the one FAIL is the **expected** gate state (served bundle is `c01317c`, not master) |
| prod `/version` `/health` | `0.1.8/884f6d0c`, `{"status":"ok","db":"ok"}` |
| prod containers | backend `Up 6 hours (healthy)`, db `Up 2 weeks` |
| prod boot log | `0` errors/exceptions in the last 2000 lines |
| prod DB | `0011` applied, `UQ_conversations_user_pair` present, 97 users / 55 conversations / **231 messages (was 207 at deploy — real traffic post-deploy, zero errors)** |
| nginx (re-verified, config not in repo) | **11 `proxy_pass` / 11 `X-Real-IP`**; awk scan for a proxying location missing the header returned nothing |
| prod `.env` | `FIREBASE_SERVICE_ACCOUNT` **absent** — confirmed by name-only listing; boot logs `WARN FIREBASE_SERVICE_ACCOUNT not set` |

## Notes for next session

- **The frontend gate tips 2026-08-06.** Today's dump read `CANARY_OK {ageDays: 7}` and the bar is
  `> 7`. Re-dump tomorrow; if it reads 8 with no `CONTENT_KEY_LOST`/canary-loss, the gate is met.
  Then bump `frontend/pubspec.yaml` 0.1.8 → **0.1.9** (it still reads 0.1.8, which is what prod
  serves) and deploy. `deploy-web.ps1` is a one-way door for web key sealing — see above.
- **What the web actually protects today**: B2a content sealing is LIVE (`d02d424` is an ancestor of
  `c01317c`); B2b **is not** (`13a9fd1` is NOT an ancestor, verified with `merge-base --is-ancestor`)
  — so message text and media keys are sealed at rest for real users, **Signal identity keys are
  still cleartext in localStorage until 0.1.9 ships**. Chronology lies here: B2b was committed ~5 h
  before `c01317c` yet is not in it. Use ancestry, never dates.
- **Android is code-complete; every remaining item is owner-side**: `.jks` off-PC backup +
  fingerprint (outranks everything — losing it ends updates for every install), then
  `FIREBASE_SERVICE_ACCOUNT` on the VM (until then `notifyFcm()` early-returns and a killed Android
  app gets nothing), then the fresh-clone real-device smoke. No code task remains.
- **Deliberate rough edge, do not "fix" blindly**: a send whose socket dropped after the server
  received it stays on the "sending" spinner until the chat is reopened, where the durable
  pending-send record repairs it by exact-ciphertext match. An ack timeout that failed the bubble
  would release the exactly-once latch and duplicate the message.
- **Now irreversible in prod**: a message BOTH participants have hidden with delete-for-me is
  hard-deleted server-side (it used to linger). Support cannot recover it. Detail:
  `2026-08-03-session-queue-items-2-3.md`.
- Queues unchanged: `.planning/full-audit/REMAINING-WORK.md` (next: BE-301 → BE-008 → BE-004) and
  `.planning/full-audit/frontend/REMAINING-WORK.md` (D1/D2 + FE-020 instrumentation). `.planning`
  holds no stale `.active_plan`.
