---
description:
alwaysApply: true
---

# CLAUDE.md — Fireplace

**Source of truth = this root file + the two tier files.** Root is cross-cutting and stays in context — read it before any Fireplace work. The tier files hold the detailed traps and are **not** auto-injected. Read the matching one **once, before your first change in that tier**, then keep it in context — do not re-read it on every edit:

- Changing anything under `frontend/` (Flutter/PWA/client) → read `frontend/CLAUDE.md` first.
- Changing anything under `backend/` (NestJS/Postgres/server) → read `backend/CLAUDE.md` first.
- Cross-tier or infra/deploy/docs → this root file is enough.

Keep root cross-cutting: if a fact only matters while editing Flutter or NestJS code, it belongs in the tier file, not here. Do not turn root back into a junk drawer.

## 1. Non-negotiable workflow

- Read this root file before any Fireplace app work, and the matching tier file before your first change in that tier (see the header rule). Main agents and spawned subagents both treat these three files as the project source of truth. When delegating, explicitly tell the subagent to read them — subagents do not inherit your loaded context.
- **This repo uses multiple git worktrees — `master` is usually NOT in your current dir.** Run `git worktree list` for the mapping (one branch per worktree). Never `git checkout` a branch already checked out in another worktree; commit to a branch from the worktree that holds it. The main `Fireplace` dir may sit on a stale feature branch — check `git status -sb` before assuming master.
- **Public repo + commit-time guardrails.** `Lentach/Fireplace` is public — a committed secret is public the instant it is pushed. A pre-commit hook in `.githooks/` scans staged changes for secrets and enforces the LATEST.md cap. Activate once per clone: `git config core.hooksPath .githooks` (install `gitleaks` for full coverage; a regex fallback runs without it). Bypass only in emergencies with `--no-verify`.
- At session start: read `.cursor/session-summaries/LATEST.md`.
- At task end: write/update `.cursor/session-summaries/YYYY-MM-DD-session.md` and `.cursor/session-summaries/LATEST.md`. Required summary sections: `# title`, `**Date:**`, `## What was done`, `## Key files`, `## Verification`, `## Notes for next session`. New LATEST entry goes on top; older entries shift to `Previous`/`Earlier`. **Hard cap: LATEST.md holds at most the 5 newest entries — when you add a 6th, delete the oldest from LATEST. Full history already lives in its dated per-session file, so nothing is lost. LATEST is the skim layer, not the archive; do not let it grow unbounded (it once reached ~24k tokens that every agent and subagent paid on read).**
- For multi-step/debug/deploy-sensitive work, use persistent planning files (`task_plan.md`, `findings.md`, `progress.md` or `.planning/<task>/`). Re-read before decisions; log failed attempts.
- Before any change: read the files you touch and trace the code paths. Code/source beats docs and old summaries.
- Scope: change only what was asked. Fix obvious bugs in edited paths; do not add unasked features, abstractions, or cleanup crusades.
- Code, comments, commit messages, logs: English. UI strings may stay localized.
- Tone: brutally blunt — lead with the verdict, no hedging, no flattery ("great question" / "you're absolutely right" are banned). Roast bad code and time-wasting rabbit holes; speak the truth even when inconvenient.
- Auto-review/code-review subagents must use the same model class as the primary session unless the user explicitly asks for a cheaper model.
- Commits: commit at natural checkpoints and `git push` in the same checkpoint (the VM deploys via `git pull`; local-only commits block it). Small/trivial fixes can go straight to `master`; bigger/riskier work uses a feature branch + PR. Feature branches do NOT auto-deploy — the VM pulls `master`, so work goes live only after PR merge. Never merge to `master` without explicit user OK.
- After modifying code files, run `graphify update .`. Docs-only changes do not need it.

## 2. Architecture map

Fireplace is a production E2E encrypted chat app:

```text
Flutter web/mobile client ⇄ NestJS backend (:3000) ⇄ PostgreSQL 16 (:5433 host)
                         REST + Socket.IO         self-hosted media volume
```

- Client: `AuthGate` → `AuthScreen` or `MainShell` → `ChatDetailScreen`; state is provider-driven. See `frontend/CLAUDE.md`.
- Backend: `AppModule` wires ~15 domain modules (auth, users, chat, messages, media, key-bundles, push, …) — authoritative full map in `backend/CLAUDE.md` §2; `ChatGateway` authenticates sockets and delegates to chat services.
- Media: current media storage is self-hosted under `/app/media` (`avatars/`, `msgs/`). Cloudinary URLs remain accepted only as legacy/backward-compatible media URLs.
- Graph context: read `graphify-out/GRAPH_REPORT.md` before architecture/codebase answers. No `graphify-out/wiki/index.md` currently exists.

## 3. Local commands

```bash
# Terminal 1: backend + DB for local dev
docker-compose up

# Terminal 2: Flutter web
cd frontend && flutter run -d chrome
```

- Ports: backend `:3000`, DB host `:5433 -> :5432`, Flutter web random unless specified.
- Before local start on Windows if stale node processes bite: `taskkill //F //IM node.exe`.
- Phone on WiFi: `cd frontend && .\run_web_for_phone.ps1`, or `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=BASE_URL=http://YOUR_PC_IP:3000`.
- Tests: `cd backend && npm test` (469 unit tests, 46 suites; verified by `node scripts/verify-claude-backend-test-counts.mjs`). Frontend: `cd frontend && flutter analyze --no-fatal-infos && flutter test`. Full-stack E2E wire harness (needs `docker-compose up` first, never in the default suite/CI): `cd frontend && flutter test test_e2e` — see `frontend/CLAUDE.md` §1.
- CI: `.github/workflows/ci.yml` runs backend tests + the CLAUDE test-count verifier, then Flutter analyze/tests.

## 4. Production deploy and safety

Production: `https://fireplace.ignorelist.com`, **OVH VPS** `ubuntu@51.68.138.13` (Warszawa, 4 GB + 2G swap, Ubuntu 24.04, key-only SSH), repo `~/fireplace`. Migrated off the GCP VM 2026-07-08; the GCP box only relays stale-DNS traffic to the VPS pending decommission — never redeploy to it.

Full runbook (paths, verification table, backup/restore, troubleshooting): `.cursor/rules/production-vm-deploy.mdc` — read it before non-trivial prod ops.

Deploy is split because small servers cannot compile Flutter web without OOM/freezing:

- Frontend deploy is from the PC: `git pull ; .\deploy-web.ps1`.
  - Script runs `flutter clean` then `flutter build web --release --no-wasm-dry-run` with `BASE_URL`, `GIT_COMMIT`, `BUILD_TIME`, `WEB_PUSH_VAPID_PUBLIC_KEY`.
  - Publishes by staging + atomic swap into `~/fireplace/frontend-build/`.
  - Verify served app via `/version.json` and Settings footer. Trust `gitCommit`, not semver alone; Flutter can serve cached code with a bumped version. Change not taking effect → `cd frontend && flutter clean` before `.\deploy-web.ps1`, and hard-bust the PWA service-worker cache (incognito tab proves it).
  - After deploy: fully close + reopen PWA. Never uninstall / clear site data to refresh — that wipes local E2E Signal keys.
- Backend deploy is on the VM: `cd ~/fireplace && ./deploy-backend.sh`.
  - Script runs `git pull --ff-only`, computes `APP_VERSION` from `frontend/pubspec.yaml`, builds the backend image from `docker-compose.prod.yml`, recreates the backend container via `up -d` (db stays up), verifies local `/version` and `/health`. Never run a bare `docker compose -f docker-compose.prod.yml up -d` by hand — without the exported `APP_VERSION`/`GIT_COMMIT` it recreates the backend at `0.0.1/unknown`.
  - Verify public backend via `curl https://fireplace.ignorelist.com/version` and `/health`.
- One-shot deploy verification: `cd scripts/smoke && node post-deploy-smoke.mjs` (one-time `npm install && npx playwright install chromium`). Checks `/health`, both version surfaces, that the served `main.dart.js` literally contains the expected git short-sha (definitive stale-build detector), and boots the app in a fresh headless browser. Defaults to local HEAD; `--commit <sha>` to check an older deploy.
- `deploy.sh` exists but is legacy/all-in-one. Do not use it as the production deploy path and never run Flutter web build on the VM.
- VM logs: `cd ~/fireplace && docker compose -f docker-compose.prod.yml logs -f --since 1m backend` (filter instrumentation with `| grep --line-buffered "<tag>"`; NestJS `this.logger.log` goes to stdout → docker logs).
- Never run `docker compose down -v`, `docker volume rm`, or `prune --volumes` on prod. `pgdata` and `media_storage` are user data.
- Testing a feature branch before merge: frontend — checkout the branch on the PC, `cd frontend && flutter clean && cd .. && .\deploy-web.ps1`, verify Settings `gitCommit` matches the branch commit, smoke-test on device. Backend — on the VPS: `git fetch origin && git checkout <branch> && ./deploy-backend.sh`, verify `/version` + `/health`. Production becomes permanent only after PR merge to `master` + normal deploy.

## 5. Version and environment contract

- User-visible app version is semver only from `frontend/pubspec.yaml`: `0.0.x`, no `+build` suffix anywhere (Settings, API, commits). "Bump version by +1" means increment the PATCH segment (`0.0.1` → `0.0.2`), never append `+1`. Production-worthy releases bump PATCH by 1; state the new version in the commit message. Docs/session-only edits do not need a bump. Minor/major bumps only on explicit ask or a clear milestone.
- Settings footer shows `version · gitCommit · buildTime` from `PackageInfo` + dart-defines.
- Flutter may still use an internal `versionCode` counter for Android store packaging; that is not the user-facing `0.0.x` string — never put `+N` in `pubspec.yaml`.
- Backend `GET /version` returns `{ version, gitCommit, buildTime }` from `APP_VERSION`, `GIT_COMMIT`, `BUILD_TIME` injected by deploy scripts.

Core env vars:

| Area | Vars |
|---|---|
| DB | `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME` |
| Auth/CORS | `JWT_SECRET` (>=32 chars, generated once and persisted; do not rotate/regenerate during normal deploys or host moves. If exposed, rotate after sticky-session refresh is deployed; valid refresh tokens can obtain new access JWTs without re-login), `ALLOWED_ORIGINS` |
| Media | `MEDIA_BASE_URL`, `MEDIA_DIR`, `MEDIA_CLEANUP_GRACE_MS`, `MEDIA_X_ACCEL_REDIRECT` |
| Push | `FIREBASE_SERVICE_ACCOUNT`, `WEB_PUSH_VAPID_PUBLIC_KEY`, `WEB_PUSH_VAPID_PRIVATE_KEY`, `WEB_PUSH_VAPID_SUBJECT` |
| Frontend dart-defines | `BASE_URL`, `GIPHY_API_KEY`, `WEB_PUSH_VAPID_PUBLIC_KEY`, `GIT_COMMIT`, `BUILD_TIME` |
| Deploy metadata | `APP_VERSION`, `GIT_COMMIT`, `BUILD_TIME` |

VAPID public key in the frontend build must match backend VAPID keys. A wrong key means web push subscribe/delivery failures; this is a stupidly easy footgun.

## 6. Database, backups, and E2E safety

- Local `docker-compose.yml`: dev only, bind-mounted backend, `NODE_ENV=development`, relaxed CORS, TypeORM auto-DDL.
- Prod `docker-compose.prod.yml`: `NODE_ENV=production`, restricted CORS, TypeORM `synchronize` OFF. Prod schema changes ship as numbered SQL files in `backend/migrations/`, applied automatically at backend boot by the migration runner (exactly-once, tracked in `schema_migrations`; a failed migration aborts boot). Entities define the dev shape; the migration files are prod truth — see `backend/CLAUDE.md` §4.
- Staging dress rehearsal (PC, not routine — a GATE for risky deploys only): `.\staging.ps1` boots the real prod compose isolated as `fireplace-staging` (backend `:3100`, db `:5533`, own volumes, dummy secrets in gitignored `.env.staging` — NEVER the real `JWT_SECRET`). Rehearse BEFORE deploying anything that touches `*.entity.ts`, manual SQL, `docker-compose.prod.yml`, `backend/Dockerfile`, or bootstrap/config code; skip it for UI work. Flow: `up` → `restore <dump>` (or `seed-schema` for entity-fresh) → `sql <migration>` (runs with `lock_timeout=10s`) → `harness` (wire harness vs prod-mode stack). It does NOT rehearse nginx/TLS, host perms, or devices.
- Raw SQL with camelCase columns needs quotes, e.g. `"deliveryStatus"`, `"createdAt"`.
- Backups: `./backup-db.sh` on VM backs up Postgres + media + encrypted `.env` when a passphrase is configured. Dumps contain ciphertext messages, public keys, usernames/contact graph/timestamps and password hashes; they cannot decrypt messages but are still sensitive.
- Backup setup: `./setup-backup-cron.sh` on the VM stores the gpg passphrase in a 0600 file (never on the cron line/argv) and installs the daily cron. Without it there are effectively no backups, or unencrypted ones (`backup-db.sh` skips `.env` and warns when no passphrase). Store the passphrase OFF the VM and decrypt-test one dump before trusting it.
- Offsite: `BACKUP_RCLONE_REMOTE=remote:bucket/prefix` on the cron line uploads encrypted artifacts (verified by listing the remote) — B2 with an append-only application key (no `deleteFiles`), pruning via bucket lifecycle. `BACKUP_HEALTHCHECK_URL` pings a dead-man monitor ONLY on full success. Details in `.cursor/rules/production-vm-deploy.mdc`.
- Restore: `./restore-db.sh <dump>` is DB-only, destructive, and wraps `pg_restore` in a single transaction; media and `.env` restore are manual.
- E2E invariant: server stores Signal ciphertext and metadata, never device private keys. Device Signal keys live locally (web localStorage / mobile secure storage). Clearing site data, uninstalling the PWA, or account deletion can destroy keys with no recovery.

## 7. Shared wire contracts

- E2E envelope: `{ content, messageType?, mediaUrl?, mediaDuration?, mediaKey?, mediaIv?, linkPreview? }`. Ciphertext format is `"{type}:{base64}"` (`3` PreKey, `2` Signal/whisper). Server stores `[encrypted]` plus metadata.
- Delete semantics:
  - Delete conversation: messages + conversation removed, friendship kept, WS `deleteConversationOnly`.
  - Unfriend: friend request + conversation + messages removed, friendship removed, WS `unfriend`.
  - Clear history: messages removed, friendship kept, WS `clearChatHistory`.
  - Delete for me: hidden for caller only, WS `deleteMessage mode=for_me`.
  - Delete for everyone: sender-only hard delete for both sides, clears pin, WS `deleteMessage mode=for_everyone`.
- Edit message: sender-only text edit within 15 minutes. Client sends a new ciphertext over the existing Signal session via WS `editMessage`; backend stays blind, replaces `encryptedContent`, stamps `editedAt`, emits `messageEdited`, rejects via `editMessageFailed` (`not_sender`, `window_expired`, `not_text`, `not_found`).

## 8. Adding cross-tier features

- New WS event: backend DTO + service handler + `@SubscribeMessage` in `chat.gateway.ts`; frontend `SocketService` emit/listen + `ConnectionProvider` routing + provider/model updates.
- New REST endpoint: backend controller/service with `JwtAuthGuard` where needed; frontend `ApiService` call + provider/screen wiring.
- New DB column: backend entity + numbered migration in `backend/migrations/` + mapper payload + frontend model `fromJson`/`copyWith` + tests. Dev auto-DDL does not mean prod is done. Rehearse the migration on the staging stack first (§6).

## 9. Agent skills

### Issue tracker

Issues live in GitHub Issues (`Lentach/Fireplace`) via the `gh` CLI; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Multi-context: `CONTEXT-MAP.md` at the root points to `backend/CONTEXT.md` and `frontend/CONTEXT.md` (created lazily); system-wide ADRs in `docs/adr/`. See `docs/agents/domain.md`.

Maintain this file by pruning. If a fact only matters while editing Flutter or NestJS code, put it in the tier file. After adding/removing backend tests, update the count in §3 so `node scripts/verify-claude-backend-test-counts.mjs` stays green.