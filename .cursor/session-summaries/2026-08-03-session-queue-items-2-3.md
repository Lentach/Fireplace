# Queue items §2 + §3 closed: delete-for-me hard-delete (backend) + expiry-sweep success diags (frontend)

**Date:** 2026-08-03 (post-B2b session)

## What was done

Closed the last two agent-actionable items from the Signal-grade hardening queue
(`2026-08-03-HANDOFF-post-b2b-state.md`). **NOTHING DEPLOYED** — the ⛔ B2b deploy
gate stands unchanged (needs `CANARY_OK {ageDays > 7}` dump + fresh owner OK; the
next frontend deploy ships B2b regardless of purpose). Backend prod also unchanged
(`0.1.2 / ded8e1a2`) — the §2 fix goes live only when the owner next runs
`./deploy-backend.sh` on the VM, which needs its own OK.

### §2 Backend hard-delete (`2d3fb81`, CI 4/4 green)

`MessagesService.hideMessageForUser` now hard-deletes the row once EVERY
conversation participant has hidden it (a row nobody can ever read again is pure
retention). Shape:

- **Atomic append, not read-modify-save**: one `UPDATE … SET "hiddenByUserIds" =
  CASE … RETURNING "hiddenByUserIds"`. Concurrent hides serialize on the row lock,
  so the second call's RETURNING carries both ids and the delete fires. The old
  read-modify-save let one hide clobber the other — the clobbered user saw the
  message resurface AND the row could never qualify (pre-existing race, now dead).
  `repo.query()` tuple trap respected (`[rows, rowCount]`).
- **Fail-closed guard**: participant set derived from the conversation relation
  (`userOne`/`userTwo`, deduplicated — never a hardcoded 2); missing relation or
  empty set = never delete. One-participant hide NEVER deletes.
- **Media before row** (backend CLAUDE.md §8), reusing `parseHiddenIds`.
- **Idempotent re-call heals legacy fully-hidden rows** (no second append; delete
  condition still evaluated). Remaining legacy fully-hidden rows self-clean only if
  ever re-hidden or expired — no migration written (would be a destructive
  migration; not asked).
- **Reply self-FK discovery (advisory-confirmed):** `messages.reply_to_message_id`
  has NO ON DELETE clause (`0001_baseline.sql:757`), so ANY hard delete of a
  replied-to message throws 23503. Fixed at source with `detachReplies()`
  (`UPDATE … SET reply_to_message_id = NULL WHERE reply_to_message_id = $1`) in
  THREE paths: the new hide hard-delete, `deleteById` (delete-for-everyone — this
  was a live prod bug: deleting a replied-to message for everyone failed), and the
  per-minute expiry cron (`MessageCleanupService` — a parent expiring before its
  reply would 23503 and wedge the cron every minute with media already unlinked).
  The vestigial scalar `"replyToMessageId"` column is never written by the entity
  path and was left alone; the mapper derives reply previews from the relation.

**Falsifications, each run RED then reverted:** (1) `every()` → `some()` — the
one-participant guard test fails; (2) empty-participant-set guard removed —
missing-conversation fail-closed test fails (vacuous `every()` on `[]` is true);
(3) `detachReplies` call removed — the detach-before-delete ordering test fails.

Tests: backend **578 → 589** (47 suites), root CLAUDE.md §3 synced same commit,
verifier OK. Lint ratchet held at baseline 816 (typed `jest.Mock<Promise<unknown>,
[string, unknown[]]>` + `unknown`-intermediate for the query result instead of
adding new unsafe-any errors).

### §3 Expiry-sweep success diags (`b1893c6`)

`EncryptionProvider.sweepDestroyablePlaintext` now logs `PLAINTEXT_SWEEP` to the
**ring** (`E2eDiagLog`, never the cap-80 durable — success is routine, noise
evicts evidence):

- Acting pass: `{expired, retired, removed, ids (sorted, capped 30),
  idsTruncated?}` — `removed` from the `purgeLocalPlaintext` result (previously
  discarded).
- Zero pass: `{expired: 0, retired: 0}` logged once per TRANSITION into
  "nothing due" (`_lastSweepFoundNothing`), re-armed by any destroying sweep. The
  sweep ticks every minute — per-tick zero entries would churn the 200-entry ring
  (the 0.1.6 noise-evicts-evidence class, one level down).
- Unconfirmable-clock hold stays SILENT by contract (root CLAUDE.md §7) — now
  test-pinned so a well-meaning "add a log here" goes red.

Tests: `test/providers/encryption_provider_sweep_diag_test.dart` (+5, real
`EncryptionService` over mock prefs + `ServerClock.observe`). Flutter
**1224 → 1229 + 10 skipped**, analyze clean, CLAUDE.md §3 synced same commit.

## Key files

- `backend/src/messages/messages.service.ts` — `hideMessageForUser` rule,
  `detachReplies`, `deleteById` detach, `MediaCleanupService` injected.
- `backend/src/messages/message-cleanup.service.ts` — cron detach before remove.
- `backend/src/messages/messages.service.spec.ts` (+11),
  `message-cleanup.service.spec.ts` (detach assertions).
- `frontend/lib/providers/encryption_provider.dart` — sweep diags.
- `frontend/test/providers/encryption_provider_sweep_diag_test.dart` (new, 5).

## Verification

- Backend: 589/589, 47 suites; lint-ratchet PASS at 816; CI run 30855372591
  success (4/4) on `2d3fb81`. Three guard falsifications run RED first.
- Frontend: 1229 + 10 skipped full suite, analyze clean; `b1893c6` pushed —
  check `gh run list --branch master --limit 1` result before any deploy.
- Local frontend count verifier NOT run standalone (it re-runs the full suite
  without `--log`; CI runs it against its own output — watch that job).

## Notes for next session

- **⛔ B2b deploy gate unchanged** — see `2026-08-03-HANDOFF-post-b2b-state.md`.
  Next frontend deploy = 0.1.7 = ships B2b + this session's sweep diags.
- **§2 goes live on the next BACKEND deploy** (owner runs `./deploy-backend.sh`;
  needs fresh owner OK). After it ships, delete-for-everyone on replied-to
  messages starts working too — that error path was silently broken in prod.
- Owner blockers still open (nag): keystore backup, `FIREBASE_SERVICE_ACCOUNT`
  + real push, fingerprint-verify peers 54 + 90. Then Android track (§5).
- Watch items on next dump unchanged (≤14 `DUP_TERMINAL_RETIRED` for known ids,
  standing escalations). After a future deploy, expect `PLAINTEXT_SWEEP` ring
  entries — one zero entry per idle stretch is correct, not a stuck sweep.
