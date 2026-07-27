# Session — Production readiness: cutover, media fix, backups, backend release blockers (2026-06-21 → 06-22)

## Outcome
Started from "is VM prod up to date?" → discovered prod was silently running in **dev mode**
(dead `/version` = `0.0.2/dev`, no rate limiting, TypeORM auto-DDL on the live DB). Ended with a
verified, hardened, **live** production backend at **`0.0.61 / b055724`**, prod mode, all gates checked.

## What shipped (all merged to master `b055724`, deployed live)
- **Healthcheck fix** (`e74be18`): `localhost`→`127.0.0.1` (busybox `::1` vs IPv4-only Nest).
- **Production backend deploy** (`b215592`, `3ba4489`): new `docker-compose.prod.yml` (built image,
  `NODE_ENV=production`, fail-fast secrets, restart policy), `deploy-backend.sh` (truthful `/version`),
  fixed latent Dockerfile entrypoint (`dist/main.js` not `dist/src/main.js`). `docker-compose.yml` = LOCAL DEV ONLY.
- **Media fix** (`7e1c196`): decoupled serving from `NODE_ENV` (prod was returning empty `X-Accel-Redirect`).
- **Backups** (PR #14, `feature/backup-hardening`): `backup-db.sh`/`restore-db.sh`/`setup-backup-bucket.sh`;
  passphrase-file (no argv leak), encrypted `.env`, GCS offsite, **atomic restore** (`--single-transaction`
  + guaranteed backend restart), flock, nullglob, partial-tar cleanup. E2E-safe (no private keys in dumps).
- **Backend release blockers** (PR #13, `fix/backend-release-blockers`): global `HttpThrottlerGuard`
  (X-Real-IP, skips WS) — HTTP rate limiting was **inert** (no guard registered); Secret Notes CSP
  (nonce + addEventListener, was broken under helmet); WS `passwordChangedAt` enforcement; `messageType`
  enum validation; user-scoped FCM-token delete; loopback port binding; NAT-tolerant limit tuning. 316 tests.
- **Uninstall warning** (PR #15, `0.0.61`): localized (en/pl) Settings note above Logout — uninstalling/
  clearing data wipes device-only E2E keys → history unreadable. Cosmetic, no crypto change.

## Production state (verified this session)
- `/version` (public, via nginx) = `0.0.61 / b055724` — prod build live.
- Schema under `synchronize:OFF`: ✅ all tables incl `refresh_tokens`, `secret_notes`; `conversations`
  pinned* ; `users.passwordChangedAt`; index `idx_messages_conv_created`.
- nginx `/etc/nginx/sites-enabled/fireplace`: ✅ all proxied locations set `X-Real-IP $remote_addr`.
- `/health` ok. Backend healthy.

## CRITICAL operational rules (gotchas learned)
- **Backend deploy is ONLY `cd ~/fireplace && git pull && ./deploy-backend.sh`.** A bare
  `docker compose up`/`restart` uses the DEV compose (same container name) and **reverts prod to dev mode**
  (`0.0.2/dev`). This happened twice this session.
- **Frontend deploy is `.\deploy-web.ps1` on the PC** (VM OOMs building Flutter web).
- `/version` truthful only after `deploy-backend.sh` (injects APP_VERSION/GIT_COMMIT).
- Harness: the `task` tool drops large/multiline payloads → spawn subagents via `eval` `agent()`.
  NEVER fan out many `slow`-model agents (hit account rate limit once).

## Open items for next session (operational, not code)
1. **In-app smoke test:** login · send · image+voice · create & reveal a Secret Note · ~30 bad logins → 429.
2. **Backups go-live:** on VM create `~/.config/fireplace/backup.pass` (chmod 600, store passphrase OFF-VM),
   run `BACKUP_PASSPHRASE=... ./backup-db.sh` once, test a restore, add the 04:00 cron (+ optional GCS bucket).
3. **Frontend deploy:** `.\deploy-web.ps1` so the `0.0.61` uninstall-warning actually shows in the PWA.
4. **Uptime monitor** on `https://fireplace.ignorelist.com/health`.
5. All feature branches merged → safe to delete locally/remote.

## Net
Backend is production-ready and live in prod mode. Remaining items are operational (backups cron, smoke
test, frontend web deploy), not code blockers.
