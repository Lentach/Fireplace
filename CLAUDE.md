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

- Read this root file before any Fireplace app work, and the matching tier file before your first change in that tier (see the header rule). Main agents and spawned subagents both treat these three files as the project source of truth.
- At session start: read `.cursor/session-summaries/LATEST.md`.
- At task end: write/update `.cursor/session-summaries/YYYY-MM-DD-session.md` and `.cursor/session-summaries/LATEST.md`. Required summary sections: `# title`, `**Date:**`, `## What was done`, `## Key files`, `## Verification`, `## Notes for next session`. New LATEST entry goes on top; older entries shift to `Previous`/`Earlier`.
- For multi-step/debug/deploy-sensitive work, use persistent planning files (`task_plan.md`, `findings.md`, `progress.md` or `.planning/<task>/`). Re-read before decisions; log failed attempts.
- Before any change: read the files you touch and trace the code paths. Code/source beats docs and old summaries.
- Scope: change only what was asked. Fix obvious bugs in edited paths; do not add unasked features, abstractions, or cleanup crusades.
- Code, comments, commit messages, logs: English. UI strings may stay localized.
- Tone: blunt, technical, no flattery.
- Auto-review/code-review subagents must use the same model class as the primary session unless the user explicitly asks for a cheaper model.
- Commits: commit at natural checkpoints and `git push` in the same checkpoint. Small/trivial fixes can go straight to `master`; bigger/riskier work uses a feature branch + PR. Never merge to `master` without explicit user OK.
- After modifying code files, run `graphify update .`. Docs-only changes do not need it.

## 2. Architecture map

Fireplace is a production E2E encrypted chat app:

```text
Flutter web/mobile client ⇄ NestJS backend (:3000) ⇄ PostgreSQL 16 (:5433 host)
                         REST + Socket.IO         self-hosted media volume
```

- Client: `AuthGate` → `AuthScreen` or `MainShell` → `ChatDetailScreen`; state is provider-driven. See `frontend/CLAUDE.md`.
- Backend: `AppModule` wires auth/users/chat/messages/media/push/health/version; `ChatGateway` authenticates sockets and delegates to chat services. See `backend/CLAUDE.md`.
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
- Tests: `cd backend && npm test` (405 unit tests, 42 suites; verified by `node scripts/verify-claude-backend-test-counts.mjs`). Frontend: `cd frontend && flutter analyze --no-fatal-infos && flutter test`.
- CI: `.github/workflows/ci.yml` runs backend tests + the CLAUDE test-count verifier, then Flutter analyze/tests.

## 4. Production deploy and safety

Production: `https://fireplace.ignorelist.com`, GCP VM in Warszawa, user `olek292`, repo `~/fireplace`.

Deploy is split because the 2 GB VM cannot compile Flutter web without OOM/freezing:

- Frontend deploy is from the PC: `git pull ; .\deploy-web.ps1`.
  - Script runs `flutter clean` then `flutter build web --release --no-wasm-dry-run` with `BASE_URL`, `GIT_COMMIT`, `BUILD_TIME`, `WEB_PUSH_VAPID_PUBLIC_KEY`.
  - Publishes by staging + atomic swap into `~/fireplace/frontend-build/`.
  - Verify served app via `/version.json` and Settings footer. Trust `gitCommit`, not semver alone; Flutter can serve cached code with a bumped version.
  - After deploy: fully close + reopen PWA. Never uninstall / clear site data to refresh — that wipes local E2E Signal keys.
- Backend deploy is on the VM: `cd ~/fireplace && ./deploy-backend.sh`.
  - Script runs `git pull --ff-only`, computes `APP_VERSION` from `frontend/pubspec.yaml`, builds `docker-compose.prod.yml`, recreates backend, verifies local `/version` and `/health`.
  - Verify public backend via `curl https://fireplace.ignorelist.com/version` and `/health`.
- `deploy.sh` exists but is legacy/all-in-one. Do not use it as the production deploy path and never run Flutter web build on the VM.
- VM logs: `cd ~/fireplace && docker compose -f docker-compose.prod.yml logs -f --since 1m backend`.
- Never run `docker compose down -v`, `docker volume rm`, or `prune --volumes` on prod. `pgdata` and `media_storage` are user data.

## 5. Version and environment contract

- User-visible app version is semver only from `frontend/pubspec.yaml`: `0.0.x`, no `+build`. Production-worthy releases bump PATCH by 1. Docs/session-only edits do not need a version bump.
- Settings footer shows `version · gitCommit · buildTime` from `PackageInfo` + dart-defines.
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
- Prod `docker-compose.prod.yml`: `NODE_ENV=production`, restricted CORS, TypeORM `synchronize` OFF. Every new prod column/index needs manual SQL and verification. Entities are source of truth; there are no real TypeORM migrations.
- Raw SQL with camelCase columns needs quotes, e.g. `"deliveryStatus"`, `"createdAt"`.
- Backups: `./backup-db.sh` on VM backs up Postgres + media + encrypted `.env` when a passphrase is configured. Dumps contain ciphertext messages, public keys, usernames/contact graph/timestamps and password hashes; they cannot decrypt messages but are still sensitive.
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
- New DB column: backend entity + manual prod SQL + mapper payload + frontend model `fromJson`/`copyWith` + tests. Dev auto-DDL does not mean prod is done.

Maintain this file by pruning. If a fact only matters while editing Flutter or NestJS code, put it in the tier file.