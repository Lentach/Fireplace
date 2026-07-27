# Session — Backend production deploy + truthful /version (2026-06-21)

## Context
Started from "is VM production up to date?" Found: frontend `/version.json` = `0.0.60` (current),
but backend `/version` = `0.0.2 / dev / ""` and container `(unhealthy)`. Diagnosed two issues and
then did the recommended infra hardening (#2 truthful version + #3 built prod image).

## What was accomplished
1. **Healthcheck fix (e74be18):** container was `(unhealthy)` because the healthcheck hit
   `http://localhost:3000` → busybox resolves `localhost`→`::1` (IPv6) while Nest listens IPv4-only
   (`0.0.0.0`). Changed to `http://127.0.0.1:3000/health`. App itself was fine (`/health` ok externally).
2. **Production backend deploy (b215592):**
   - **Root cause of dead `/version`:** `docker-compose.yml` ran the backend as base `node:20-alpine`
     + bind-mount + `start:dev` (NODE_ENV=development), with **no `build:`** — so `docker compose build`
     was a no-op and version build-args never applied. Prod was running in dev/watch mode.
   - **Latent entrypoint bug:** `backend/scripts/*.ts` (outside `src/`) shifted tsc's root so build
     output was `dist/src/main.js`, not `dist/main.js` — Dockerfile `CMD node dist/main.js` / `start:prod`
     would crash. Fixed by excluding `scripts/` in `tsconfig.build.json` → canonical `dist/main.js`.
   - **`docker-compose.prod.yml` (new, VM-only):** built image (`fireplace-backend:latest`),
     `NODE_ENV=production`, `restart: unless-stopped`, IPv4 healthcheck, fail-fast `${VAR:?}` on
     `ALLOWED_ORIGINS/MEDIA_BASE_URL/JWT_SECRET/WEB_PUSH_VAPID_*`. db kept identical to dev (no recreate).
   - **`deploy-backend.sh` (new, exec):** git pull → compute APP_VERSION (pubspec)/GIT_COMMIT/BUILD_TIME
     → `.env` preflight → build → `up -d backend` → wait healthy → curl `/version`+`/health`.
   - **`backend/Dockerfile`:** modernized npm (`npm ci` / `npm ci --omit=dev`), ARG→ENV version, prod default.
   - **`docker-compose.yml`:** header marked LOCAL DEV ONLY.
   - **Docs:** rewrote `.cursor/rules/production-vm-deploy.mdc`; updated root `CLAUDE.md` deploy quick-ref.

## Verified locally
- `npm run build` → `dist/main.js` exists (canonical entry restored).
- `docker compose -f docker-compose.prod.yml config` resolves: NODE_ENV=production, built image,
  no dev `command`, APP_VERSION wired; `${VAR:?}` errors when a secret is truly unset.
- deploy-backend.sh exec bit `100755`; `.gitattributes` enforces `*.sh eol=lf` (safe on VM).
- NOT verified locally: actual `docker build` (Docker Desktop daemon off). Acceptance = run on VM.

## Cutover (user runs on VM) — PENDING
```bash
cd ~/fireplace && ./deploy-backend.sh
```
Expected: `/version` → version=0.0.60, gitCommit=<sha>; container `(healthy)`.

## Risks / behavioral shifts to confirm
- **NODE_ENV=production tightens CORS to `ALLOWED_ORIGINS`** — must include
  `https://fireplace.ignorelist.com` in `~/fireplace/.env` (preflight + `${VAR:?}` guard this).
- **TypeORM `synchronize` turns OFF** in prod — schema is already current from the dev period;
  future entity changes need manual SQL (see backend/CLAUDE.md). No pending schema change in recent commits.
- `secret_notes` table auto-create needs NODE_ENV!=production — table already exists from dev period.

## Notes for next session
- CI already exists at `.github/workflows/ci.yml` (could be extended to build web + push artifact).
- Still recommended (not done): Postgres `pg_dump` backups (no backup currently); external uptime
  monitor on `/health`; restart policy on db service.

## Addendum — #4 backups + #5 resilience (2b1fb4b)
- `backup-db.sh`: pg_dump -Fc chatdb + tar fireplace_media_storage → ~/fireplace-backups (0700),
  retention prune (14d), optional gpg-AES256 (BACKUP_PASSPHRASE) + GCS offsite (BACKUP_GCS_BUCKET).
- `restore-db.sh`: (decrypt) → stop backend → pg_restore --clean → start.
- E2E-safety confirmed: dumps hold ciphertext + public keys + metadata + bcrypt hashes only;
  Signal private keys are device-only → a dump cannot decrypt messages.
- docker-compose.prod.yml: restart: unless-stopped on db (backend already had it).
- rule: Backups & monitoring section (external /health uptime monitor recommended).
- Scripts bash-syntax-checked (git sh -n) clean; actual run is on the VM.
- OPEN: confirm ALLOWED_ORIGINS in ~/fireplace/.env before cutover; set backup cron; sign up /health monitor.

## DEPLOYED & VERIFIED LIVE (2026-06-21)
- Cutover done on VM. `/version` truthful (local + public): version=0.0.60, gitCommit=<sha>.
- Footgun fixed (3ba4489): `deploy-backend.sh` now runs `up -d` (both services) WITH version env;
  a bare `docker compose up -d` had recreated backend at the Dockerfile default 0.0.1 — never do that by hand.
- **Media regression fixed (7e1c196) — VERIFIED WORKING:** in prod the media controller returned an
  empty 200 + `X-Accel-Redirect` (nginx has no `/internal/media/` location; files are in a docker volume),
  so all images/gifs/voice/avatars broke after the dev→prod cutover. Serving is now decoupled from
  NODE_ENV — bytes streamed directly by default; X-Accel offload opt-in via `MEDIA_X_ACCEL_REDIRECT=true`.
- Prod backend now: built `fireplace-backend:latest`, NODE_ENV=production, healthy, restart:unless-stopped.
- STILL OPEN (operational, user): backup cron (`backup-db.sh` + crontab) + one test restore; external
  `/health` uptime monitor. Optional: extend `.github/workflows/ci.yml` to build the web bundle.
