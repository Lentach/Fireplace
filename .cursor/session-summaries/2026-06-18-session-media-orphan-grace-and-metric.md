# Media-orphan gap (I1) — cron grace period + orphan observability

**Date:** 2026-06-18

## What was done
Closed the two halves of the I1 media-orphan gap **without touching the upload→send ordering or the E2E envelope** (metadata-only).

**Problem 1 — cron race (correctness):** `cleanupOrphanedFiles()` (daily 03:00) deleted ANY file not referenced by a non-expired row, including a blob uploaded seconds ago whose `sendMessage` emit/persist is still in flight → a 03:00 run overlapping a send could delete a blob a legit message is about to reference.

**Problem 2 — no observability:** no metric/log distinguished genuine orphans (upload-ok, send-failed) from expired media, so orphan rate was unmeasurable.

### Backend (`media-cleanup.service.ts`)
- **Grace period:** before deleting an unreferenced file, `fs.stat` it and SKIP if `now - mtime < graceMs`. Default `15 min`, env-overridable via `MEDIA_CLEANUP_GRACE_MS`. Uses **file mtime**, not message timestamps. A grace-skipped file is deleted on a later run once it ages past the window and is still unreferenced.
- **Classification + summary:** method now returns `MediaCleanupSummary { scanned, deleted, orphan, expired, graceSkipped }` and logs it to stdout (→ docker logs). Two queries: non-expired set (kept) + all-referenced set (regardless of expiry). A deleted file referenced by some (expired) row ⇒ **EXPIRED**; referenced by no row ⇒ **ORPHAN** (the upload-ok/send-failed gap).
- Containment + expiry logic preserved; grace is purely additive.

### Frontend (`messaging_provider.send.dart`)
- `_encryptAndSend` logs `MEDIA_ORPHAN_LIKELY{tempId}` to `E2eDiagLog` (via `_e2eFlowLog`) on both failure paths (`!e2eReady` and the catch) **only when a non-empty `mediaUrl` is present** — i.e. the blob was uploaded but the send failed → orphan-likely. New `_logMediaOrphanLikely(tempId, mediaUrl)` helper; id-only, no plaintext/keys/URL. Text/ping sends never log it (no upload).

### Retry-reupload follow-up — checked, NOT a problem
Verified `retryFailedMessage`: for voice/image/gif/file it **reuses** the model's `mediaUrl`+`mediaKey`+`mediaIv` and re-runs the E2E send only (no re-upload). The re-upload branch (voice → `sendVoiceMessage` with `localAudioPath`) fires only when the original upload never produced a URL — i.e. no orphan to multiply. `_retrySendInPlace` (auto-retry) handles text/ping only. So retry does NOT create additional orphans. No follow-up needed.

## Key files
- `backend/src/media/media-cleanup.service.ts` — grace period, `MediaCleanupSummary`, orphan/expired classification, `resolveGraceMs()` + `MEDIA_CLEANUP_GRACE_MS`
- `backend/src/media/media-cleanup.service.spec.ts` — +3 tests (grace-skip recent; delete old orphan; orphan-vs-expired counts), existing orphan files backdated past grace via `fs.utimes`
- `frontend/lib/providers/messaging/messaging_provider.send.dart` — `_logMediaOrphanLikely` + 2 call sites in `_encryptAndSend`
- `frontend/test/providers/messaging_provider_media_send_test.dart` — +2 tests (logged after upload failure; NOT logged for text send)
- `CLAUDE.md` — test count 307→310; I1 note (grace + observability + retry-reuse verdict); cleanup-cron note; `MEDIA_CLEANUP_GRACE_MS` env row

## Verification (TDD: RED→GREEN)
- Backend spec RED first (compile error: `cleanupOrphanedFiles` returned `void`; grace not implemented) → GREEN: `npx jest --config jest.config.json src/media/media-cleanup.service.spec.ts` = **10 passed** (was 7).
- Frontend test RED first (no `MEDIA_ORPHAN_LIKELY` logged) → GREEN: `flutter test test/providers/messaging_provider_media_send_test.dart` = **11 passed**.
- Full backend suite: **310 passed, 40 suites**. `node scripts/verify-claude-backend-test-counts.mjs` → `OK: CLAUDE.md matches Jest (310 tests, 40 suites)`.
- Full frontend suite: **386 passed**. `flutter analyze` (changed files) → No issues found.

## Notes for next session
- **Backend-only behaviour change + frontend diag.** Deploy implication: goes live after merge to `master` via `git pull && docker compose restart backend` on the VM (no image build). Frontend diag is observe-only; ships with the next web deploy. **Not version-bumped** (no user-facing frontend behaviour change).
- **On-device / VM verification still owed (Untested = not done):** after deploy, tail `docker compose logs -f --since 1m backend | grep "Cron cleanup done"` to see the new `scanned/deleted/orphan/expired/graceSkipped` line; confirm a freshly-uploaded blob is NOT swept by a manual cron trigger (or lower `MEDIA_CLEANUP_GRACE_MS` to repro in-flight protection). Watch `E2eDiagLog` for `MEDIA_ORPHAN_LIKELY` frequency to gauge real orphan rate.
- No metrics backend exists → "metric" = structured stdout log (per the prompt's clarify assumption).
