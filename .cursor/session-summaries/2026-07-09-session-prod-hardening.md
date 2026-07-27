# Production hardening: SQL migrations, user FKs, non-root container, backup verification

**Date:** 2026-07-09

## What was done

Owner picked items 1–4 from a production-readiness gap review (branch `feat/prod-hardening`, 0.0.102, PR pending):

1. **SQL migration system** — `backend/migrations/*.sql` applied at backend boot by new `backend/src/database/migration-runner.ts` (called in `main.ts` BEFORE Nest creates the app, all environments). Exactly-once by filename in `schema_migrations`, lexical order, per-file transaction with `lock_timeout=10s`, `pg_advisory_lock` against concurrent boots, `RESET ALL` between files (a pg_dump baseline clears `search_path` session-wide — real trap, handled). Failed migration = boot aborts = container never healthy = `deploy-backend.sh` fails loudly.
   - `0001_baseline.sql`: full schema (pg_dump of entity-synced dev DB at `4d495da`, pre-FK). **Stamp semantics:** executed ONLY on an empty DB; on any DB that already has tables (live prod, dev) it is recorded as applied WITHOUT executing. Only the baseline is ever stamped — everything later runs everywhere (a naive "stamp all pending" would have silently skipped 0002 on prod).
2. **User FKs (migration `0002_user_foreign_keys.sql`)** — orphan-row cleanup then `ON DELETE CASCADE` FKs to `users`: `key_bundles.userId`, `one_time_pre_keys.userId`, `fcm_token.userId`, `web_push_subscription.userId`, `secret_notes.creatorId` (CASCADE on notes deliberate: account deletion destroys everything; notes expire ≤12h anyway). ADD CONSTRAINT guarded per (table, column) so dev DBs with synchronize-made hash-named FKs get no duplicates. Entities gained matching `@ManyToOne` relations; scalar `userId`/`creatorId` columns stay the API — zero service-code changes.
3. **Non-root container** — `backend/Dockerfile` runtime now `USER node` (uid 1000), copies `migrations/`, owns `/app/media`. Existing root-owned media volumes chown'd idempotently by `deploy-backend.sh` (verified live volume name `fireplace_media_storage` on the VPS) and `staging.ps1` (`Set-MediaVolumeOwnership`).
4. **Backup verification (VPS)** — cron live (04:00 daily, ran this morning), passphrase file `0600`, prune working; decrypt-tested TODAY's artifacts: DB dump → `PGDMP` magic, `.env` decrypts, media tar lists. **Gap flagged, NOT fixed: no `BACKUP_GCS_BUCKET` on the cron line — backups are VM-local only, no offsite.**

New deps: `dotenv` (runner env loading, was transitive), `@types/pg` (dev).

## Key files

- `backend/src/database/migration-runner.ts` + `migration-runner.spec.ts` (9 tests, Tester-written)
- `backend/migrations/0001_baseline.sql`, `backend/migrations/0002_user_foreign_keys.sql`
- `backend/src/main.ts` (runner call), 5 entities (`key-bundle`, `one-time-pre-key`, `fcm-token`, `web-push-subscription`, `secret-note`)
- `backend/Dockerfile`, `deploy-backend.sh`, `staging.ps1`
- Docs: root `CLAUDE.md` §3 (416/43) §6 §8, `backend/CLAUDE.md` §3 §4 §12, `.cursor/rules/production-vm-deploy.mdc`
- `frontend/pubspec.yaml` → 0.0.102

## Verification

- Backend Jest **416/416, 43 suites** + count verifier OK (was 407/42).
- Dev stack: watch-mode boot stamped 0001 + applied 0002 against the existing dev DB; `/health` ok; CASCADE FKs confirmed in catalog.
- **Staging dress rehearsal (full gate):**
  - `up` on EMPTY DB → baseline EXECUTED (12 public tables), backend healthy as `node`, `/app/media` writable.
  - Restored TODAY's real prod dump (decrypted on the VM — passphrase never left it), reproduced prod's exact state (`DROP SCHEMA` first; the initial restore attempt failed against the post-FK staging schema — see trap below), backend boot logged `stamped 0001` + `applied 0002`; all 5 `fk_*` CASCADE constraints asserted via `pg_constraint`; data intact (80 users, 489 messages).
  - Wire harness vs staging: **7/7 passed**.
- **New documented trap:** `pg_restore --clean` of a pre-FK dump onto a post-FK DB fails (dump can't drop constraints it doesn't know) → wipe schema first; runbook updated.
- **Adversarial review (PR #55, same model class): MERGE-READY, zero P1.** Reviewer verified by EXECUTION: stamp rule on scratch DBs, orphan-DELETE selectivity, FK-guard idempotence + TypeORM hash-FK detection, non-root write surface (multer = memoryStorage, no root temp files), MIGRATIONS_DIR in all three run modes. **P2-1 fixed (`e1db060`):** bounded db-connect retry (10×3s, fresh pg Client per attempt — a failed Client cannot re-`connect()`) so VM cold starts don't crash-loop the backend before Postgres is up; smoke-tested vs a dead port (ECONNREFUSED surfaced by code — AggregateError.message is empty). P3s accepted as-is (first-deploy chown window self-heals; alpine:3 pull gates deploy fail-safe; RESET ALL vs DISCARD ALL confirmed correct).

## Notes for next session

- **PR merge + deploy owed:** after merge, VM `./deploy-backend.sh` (migrations run automatically at boot; watch for `[Migrations] stamped/applied` in logs, then `curl /version` = 0.0.102). Frontend deploy optional (no frontend runtime change; pubspec bump only shows after next `deploy-web.ps1`).
- First prod deploy also chowns the media volume — verify media upload works post-deploy (send an image).
- **Offsite backups (same session, PR #56 `feat/offsite-backups`, AWAITING MERGE):** owner chose option B (B2 + rclone). `backup-db.sh` gained `BACKUP_RCLONE_REMOTE` (encrypted-only upload, VERIFIED by listing the remote — count match, rclone exit code not trusted; `lsf` stage guarded so a broken remote can't abort the script under `set -euo pipefail`) and `BACKUP_HEALTHCHECK_URL` (dead-man ping ONLY on full success). rclone v1.60.1 installed on the VPS. Live-fired all three paths on the VPS with a local rclone destination: success `verified 3/3` + ping; broken remote → `ERROR 0/3`, prune still runs, ping SKIPPED. **Owner-side activation owed (~10 min, checklist in PR #56):** B2 account + private bucket + lifecycle 30d, application key WITHOUT `deleteFiles` (append-only), `rclone config` on the VM (conf 0600), healthchecks.io check (24h period / 2h grace), cron line update, then the acceptance drill: download one artifact FROM B2 and decrypt-check `PGDMP`. LATEST.md deliberately not edited on this branch (PR #55 owns today's entry; would conflict).
- `deploy.sh` (legacy) untouched; still not a deploy path.
