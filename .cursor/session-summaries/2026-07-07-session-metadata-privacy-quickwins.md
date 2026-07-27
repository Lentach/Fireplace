# Metadata Privacy — Quick Wins Implemented (content-free push, log min, backup cron) — 0.0.91

**Date:** 2026-07-07 (implementation; follows the same-day audit session)

## What was done
Implemented the top-3 quick wins from the metadata-privacy audit (`docs/audit/2026-07-07-metadata-privacy-audit.md`). Branch `feat/metadata-privacy-hardening`, commit `6015b6b`, pushed to origin. **PR + backend deploy owed; NOT merged to master.** No content-E2E change; frontend bundle unchanged.

Threat model reminder: single self-hosted server, operator=owner → these defend **breach/seizure/backup theft + third-party push relays**, not "the operator."

1. **Content-free push (biggest third-party leak):**
   - `notifyFcm` (`push-notifications.service.ts`): FCM `data` now carries ONLY `{ type:'new_message', conversationId }`. Removed `senderName` + `unreadCount/Total/ConversationIds` — those transited **Google readable**. Verified the Android FCM handler (`android_fcm_local_notifications.dart:110-149`) never read senderName (hardcoded 'Fireplace' title, generic body) → **zero UX change**.
   - `notifyWebPush`: dropped the `topic: conv-<id>` header — it's **cleartext to the push relay** (Mozilla/Apple/Google) and leaked per-conversation cadence. The web-push BODY is encrypted to the browser, so senderName/counts stay in it (still private) → web push UX unchanged.
2. **Log minimization + retention caps:**
   - Demoted per-message emit logs (`chat-message.service.ts:106,110` incl. the online-roster dump), FCM/WebPush "attempted"/cleanup logs, and key-bundle/OTP logs (`key-bundles.service.ts:47,58`) from `log`→`debug` (prod logger is error/warn/log → these are now prod-silent). Stripped the raw `endpoint` from the web-push delivery-failed `warn`.
   - `docker-compose.prod.yml`: added `logging: json-file max-size 10m / max-file 3` to `db` + `backend` (were unbounded).
3. **Backups:** new `setup-backup-cron.sh` (exec bit set in git index via `--chmod=+x`) — stores gpg passphrase in a 0600 file (never on argv/cron line), installs the daily cron, optional GCS bucket, prints a decrypt-test runbook. Closes the "backups exist but were never enabled on the VM" gap.

## Key files
- `backend/src/push-notifications/push-notifications.service.ts` — FCM strip, web-push topic drop, log demotions.
- `backend/src/push-notifications/push-notifications.service.spec.ts` — +2 regression tests (Tester agent): FCM data content-free; no web-push topic.
- `backend/src/chat/services/chat-message.service.ts`, `backend/src/key-bundles/key-bundles.service.ts` — log demotions.
- `docker-compose.prod.yml` — log rotation caps.
- `setup-backup-cron.sh` — NEW helper.
- `CLAUDE.md`, `backend/CLAUDE.md`, `AGENTS.md` — push contract §9, docker log note, backup helper §6, test count 405→407.
- `frontend/pubspec.yaml` — 0.0.90 → 0.0.91.

## Verification
- `cd backend && npm run build` — clean (nest build).
- `cd backend && npm test` — **407 passed, 42 suites** (was 405; +2 push-privacy tests).
- `node scripts/verify-claude-backend-test-counts.mjs --log backend/test-output.txt` — **OK (407/42)** (log then deleted).
- `graphify update .` — rebuilt (7938 nodes).
- Frontend NOT rebuilt/tested — no frontend code changed (bundle identical; only pubspec version).

## Notes for next session
- **Owner action (order matters — AGENTS.md: test the branch BEFORE merge):** (1) On the VM, `git fetch origin && git checkout feat/metadata-privacy-hardening && cd ~/fireplace && ./deploy-backend.sh`; verify `/version` (should read 0.0.91 after this build) + `/health`. (2) Run the push device-QA below on the branch build. (3) ONLY THEN, with your explicit OK, open PR and merge to master. A feature branch does NOT auto-deploy; live prod becomes permanent after merge + the normal prod deploy. Frontend bundle unchanged (no `.\deploy-web.ps1` needed for the push change); the 0.0.91 string surfaces in backend `/version` after `deploy-backend.sh`, and in the frontend footer only if you also redeploy web.
- **Device QA (important given push is bug-prone):** after backend deploy, smoke-test that (a) native/PWA push still WAKES and shows a notification, (b) FCM native shows generic "You have a new message" (expected — senderName was never shown there anyway), (c) web-push PWA still shows senderName in the notification (body is encrypted, unaffected), (d) tapping still deep-links to the conversation (conversationId retained).
- **Backups:** run `./setup-backup-cron.sh` ON THE VM (needs your passphrase, stored off-box). Then manual `./backup-db.sh` once + decrypt-test a dump.
- Remaining roadmap items (report Phase 3, own future prompts, gated on owner Qs): opt-in read-receipts/typing (Q1), timestamp coarsening (Q4), padding to size buckets, and the big one — ephemeral-by-default delete-on-delivery (Q5). None implemented.
- The audit report `docs/audit/2026-07-07-metadata-privacy-audit.md` stays LOCAL (gitignored; public repo).
