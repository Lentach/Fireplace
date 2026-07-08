# Local production dress-rehearsal stack (staging.ps1)

**Date:** 2026-07-08 (same session as the E2E wire harness; wishlist item #3)

## What was done

Built the last open item from the tooling wishlist: a **local prod dress rehearsal** — the real `docker-compose.prod.yml` stack (built image, `NODE_ENV=production`, TypeORM `synchronize:OFF`, restricted CORS) booted isolated on the dev PC as compose project `fireplace-staging` (backend `127.0.0.1:3100`, db `127.0.0.1:5533`, own volumes, `restart: no`).

**Positioning (from review, agreed): a GATE, not a ritual.** Rehearse only deploys touching `*.entity.ts`, manual SQL, `docker-compose.prod.yml`, `backend/Dockerfile`, or bootstrap/config code — the class of bug prod's `synchronize:OFF`/no-migrations setup is structurally blind to until live (the secret-notes 42703 family). Explicit non-goals: nginx/TLS, host perms, devices/PWA.

Components:
- `docker-compose.staging.yml` — ~15-line overlay (ports `!override` — compose ≥2.24 — restart off, `NODE_ENV` flippable via `STAGING_NODE_ENV` for the seed boot).
- `.env.staging.example` → gitignored `.env.staging` with **dummy secrets by design** (a staging stack holding the real `JWT_SECRET` would mint valid prod tokens; garbage VAPID keys are safe — `setVapidDetails` failure is caught, push just disables).
- `staging.ps1` — `up` (warns on empty schema) / `seed-schema` (one-shot dev-mode boot creates schema from entities, flips back to production) / `restore <dump[.gpg]>` (gpg decrypt in a throwaway container, passphrase prompted never stored, `pg_restore --clean --single-transaction`) / `sql <file>` (`ON_ERROR_STOP` + `PGOPTIONS lock_timeout=10s` so DDL fails fast instead of hanging behind a transaction) / `harness` (wire harness vs `:3100` via `E2E_BASE_URL`) / `status` / `down` / `destroy` (confirmed, wipes volumes).

Migration workflow now: `up` → `restore <latest-dump>` → `sql migration.sql` → `harness` → green → same SQL on VPS → `deploy-backend.sh`.

## Key files
- `docker-compose.staging.yml`, `.env.staging.example`, `staging.ps1` — NEW
- `.gitignore` — `.env.staging`
- `CLAUDE.md` §6 (gate rule + flow) and §8 (New DB column → rehearse first)

## Verification
- `seed-schema`: dev-boot created **11 tables** from entities, flipped to `NODE_ENV=production`, healthy; `/version` truthful (`0.0.96/ff3ca15` on `:3100`).
- **Wire harness 7/7 against the prod-mode stack** — first time the full E2E contract ever ran under production config off the VPS.
- `sql`: smoke migration (SELECT + ADD/DROP COLUMN) applied; verified again after the `lock_timeout` addition. `up`/`down` persistence of volumes confirmed.
- NOT verified (by nature): `restore`'s gpg decrypt path (needs the owner's passphrase; its cp/pg_restore plumbing is the same hardened pattern as the verified `sql`), `destroy`.

## Traps hit (documented for reuse)
- **PowerShell 5.1 + BOM-less UTF-8**: em-dashes misdecode into curly quotes that BREAK string parsing. `staging.ps1` must stay pure ASCII.
- **`docker cp` file→existing-directory places the file INSIDE it** — an aborted run left `/tmp/staging.sql` as a directory and poisoned retries ("Is a directory"). Both `sql` and `restore` now pre-clean the target with `rm -rf` and validate the source is a file.

## Notes for next session
- Rehearse `restore` once with a real dump (owner passphrase at prompt) before trusting the flow for a live migration.
- Commit went via branch `feat/staging-rehearsal` + PR — merge OK owed by owner.
