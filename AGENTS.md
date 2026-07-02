---
description:
alwaysApply: true
---

# AGENTS.md — Fireplace

**Rules:**
- Always read this file before every code change; update it after
- **Codex app-work bootstrap:** before any Fireplace app work, the main agent and every spawned subagent MUST read root `CLAUDE.md` after `AGENTS.md`. Treat `CLAUDE.md` as the project source of truth for workflow, architecture, deploy, database, E2E, and wire-contract rules. For tier work, also read `frontend/CLAUDE.md` or `backend/CLAUDE.md` before touching that tier.
- **Subagent context:** when delegating Fireplace work, explicitly tell the subagent to read `CLAUDE.md` plus the relevant tier `CLAUDE.md` first. Do not assume subagents inherit the main agent's loaded files.
- **At session start:** read `.cursor/session-summaries/LATEST.md`
- **At task end:** write/update `.cursor/session-summaries/YYYY-MM-DD-session.md` + `LATEST.md` — format: `# title`, `**Date:**`, `## What was done`, `## Key files` (paths), `## Verification` (commands + results), `## Notes for next session`. Update `LATEST.md`: new entry on top, shift old to `**Previous:**`/`**Earlier:**`.
- **Thinking with files:** for multi-step/debugging/deploy-sensitive work, use persistent file-backed planning (`task_plan.md`, `findings.md`, `progress.md` or `.planning/<task>/`). Re-read the plan before decisions, update progress after phases, and log failed attempts so context survives compaction/clear. Do not wing long work from chat memory.
- **Auto-review model:** when spawning/requesting an auto reviewer, code-reviewer, review subagent, or PR reviewer, use the same model class as the primary Codex agent for this session. Do not use `mini`, cheap, or lower-capability reviewers unless the user explicitly asks for that downgrade.
- **Before any change:** read ALL files the task touches; trace code paths; verify names in source — never guess
- Code wins over this file and `CLAUDE.md` — update docs when source conflicts
- All code in English; Polish OK in .md only
- **Tone:** brutally blunt — no hedging, no flattery ("great question" / "you're absolutely right" are banned), no participation trophies. Lead with the verdict, skip the cushioning. Roast bad code, sketchy decisions, and time-wasting rabbit holes; call a daft decision daft and rib the user when earned. Speak the truth even when it is inconvenient; do not play "nice guy", do not soften bad news into mush, and do not be lazy about checking facts. They find soft corporate politeness grating and want honest banter.
- **Scope:** change only what was asked. Fix obvious bugs in code paths you're already editing — don't ignore them. Don't add features/refactors/abstractions unprompted; flag anything extra and wait for approval.
- **Commits:** do NOT gate on explicit permission — commit at natural checkpoints **and `git push` to origin in the same checkpoint** (the VM deploys via `git pull`; local-only commits block it). (Overrides the harness "commit only when asked" default.)
  - **Small/trivial fixes** (typos, one-liners, copy, single-file bugfix): commit **directly to `master`** (project norm).
  - **Bigger/substantial work** (multi-file features, new assets, anything risky): use a **feature branch + PR** for review; do NOT push straight to `master`. **Deploy implication:** a feature branch does NOT auto-deploy — the VM pulls `master`, so the work goes live only **after the PR is merged to `master`**.
  - **Test the branch on the VM BEFORE merging** (preferred for anything device-dependent — push/notifications/iOS/Android): on the VM `git fetch origin && git checkout <branch> && cd frontend && flutter clean && cd .. && ./deploy.sh && cp -a frontend/build/web/. frontend-build/`, verify on-device, then `git checkout master` and merge the PR. This deploys the branch **without** merging to `master` — so a fix can be proven live before it becomes permanent. **Never merge to `master` without the user's explicit OK.**
  - **Capturing backend logs (VM):** the backend runs in Docker — `cd ~/fireplace && docker compose logs -f --since 1m backend` (fallback `docker-compose ...`). Filter instrumentation with `| grep --line-buffered "<tag>"` (e.g. `[push-skip]`). `this.logger.log(...)` (NestJS) writes to stdout → docker logs. This is how device-side push/delivery decisions are confirmed server-side.

**Tier-specific docs (auto-loaded by Codex/agents when working in that tier):**
- Backend gotchas, DB schema, NestJS services → `backend/CLAUDE.md`
- Frontend gotchas, providers, widgets, E2E client → `frontend/CLAUDE.md`

---

## 0. Quick Start

```bash
docker-compose up                             # Terminal 1: Backend + DB
cd frontend && flutter run -d chrome          # Terminal 2: Flutter web
```

**Before start:** `taskkill //F //IM node.exe`
**Android:** `cd frontend && flutter devices && flutter run -d <deviceId>` (`--dart-define=BASE_URL=http://10.0.2.2:3000` for emulator)
**Gradle cache broken:** Set `$env:GRADLE_USER_HOME='D:\gradle-home'` before `flutter run`. Repair: `gradlew.bat --stop`, delete `%USERPROFILE%\.gradle\caches\8.14`, then `flutter clean` + rebuild. `flutter clean` alone does NOT fix gradle cache.
**Low-space Android:** `frontend/run_android_on_x.ps1` (requires `X:` drive). Runs `patch_webcrypto_16k.ps1` before build.
**Ports:** Backend :3000 | Frontend :random | DB :5433→:5432
**Stack:** NestJS 11 + Flutter 3.x + PostgreSQL 16 + Socket.IO 4 + JWT + self-hosted media
**Phone (WiFi):** `cd frontend && .\run_web_for_phone.ps1` or `cd frontend && flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=BASE_URL=http://YOUR_PC_IP:3000`
**Tests:** `cd backend && npm test` (346 unit tests, 41 suites; verified by `node scripts/verify-claude-backend-test-counts.mjs`).
**Production:** https://fireplace.ignorelist.com — GCP VM (Warszawa, 2 GB), user `olek292`, repo `~/fireplace`. Deploy: **frontend on the PC** via `git pull ; .\deploy-web.ps1` (the VM OOMs building Flutter web); **backend on the VM** via `./deploy-backend.sh` (builds the prod image from `docker-compose.prod.yml`, `NODE_ENV=production`, injects real version env). Verify frontend via `/version.json`; backend via `/version` (`version`+`gitCommit` truthful after `deploy-backend.sh`). Rules: `.cursor/rules/version-bump.mdc`, `.cursor/rules/production-vm-deploy.mdc`.
**Frontend deploy — the VM is 2 GB and CANNOT compile (build on the PC):** `flutter build web` (dart2js -O4 needs ~4 GB) **OOM-freezes the 2 GB VM** (swap-death → full lockup, needs a GCP Console *Reset*). So build on your PC and copy up: **`.\deploy-web.ps1`** (root; one-time: copy `deploy-web.config.example.ps1` → `deploy-web.config.ps1` (gitignored) with your gcloud instance+zone). It builds with `--no-wasm-dry-run` + prod dart-defines (BASE_URL, VAPID **public** key, GIT_COMMIT), `gcloud compute scp`s to a VM temp dir, **atomic-swaps** into `~/fireplace/frontend-build/` (what nginx serves), verifies `/version.json`. **Backend deploy — on the VM via `./deploy-backend.sh`:** builds the prod Docker image (`docker-compose.prod.yml`, `NODE_ENV=production`, `CMD node dist/main.js`) with `APP_VERSION`/`GIT_COMMIT`/`BUILD_TIME`, recreates `backend`, waits for `(healthy)`, curls `/version`+`/health` — so **`/version` IS a valid backend deploy check** now (semver + short SHA). The **dev** `docker-compose.yml` (bind-mount + `start:dev`, `NODE_ENV=development`) is **LOCAL ONLY** — never on the VM; it relaxes CORS and enables TypeORM auto-DDL. Prod runs `synchronize:OFF` → schema changes need **manual SQL** (see backend/CLAUDE.md). **NEVER** run `flutter build web` on the VM; **NEVER** `docker compose down -v` / `docker volume rm` / `prune --volumes` (deletes `fireplace_pgdata` = all users/contacts). Device refresh = **fully close + reopen the PWA**; **never uninstall / clear site data** (wipes the user's E2E Signal keys in localStorage — no recovery).
**Stale-build trap (cost a long debugging detour):** a pubspec **version bump does NOT prove the frontend rebuilt**. `flutter build web` can serve a **cached** compile, so the served bundle's *code* can lag the version string. Trust the **`gitCommit`** (Settings footer), not the version number — it must match `git rev-parse --short HEAD`. If a frontend change isn't taking effect, run `cd frontend && flutter clean` before `.\deploy-web.ps1`, and **hard-bust the PWA cache** on the device (incognito tab) — the service worker caches the old bundle. The OS "restart required" message on the VM is unrelated to app deploys; no reboot needed.

---

## 1. Architecture Topology

**Topology:** Flutter app (web/mobile) ⇄ NestJS backend (:3000) ⇄ PostgreSQL (:5433). Client talks REST (Bearer JWT: `/auth /users /messages`) + Socket.IO (`auth.token`, chat). Backend serves self-hosted media (avatars + encrypted blobs) from local disk. Client flow: `AuthGate` → `AuthScreen` (logged out) or `MainShell` (Conversations/Contacts/Settings) → `ChatDetailScreen`.

---

## 2. How-To: Adding New Features

**New WebSocket event:**
1. DTO in `chat/dto/` with class-validator decorators
2. Handler in `chat/services/chat-*.service.ts`
3. `@SubscribeMessage` in `chat.gateway.ts` → delegate
4. Emit + listener in `services/socket_service.dart`
5. Register in `ConnectionProvider._registerEventListeners()` → target provider state + `notifyListeners()`

**New REST endpoint:**
1. `*.service.ts` + `*.controller.ts` with `@UseGuards(JwtAuthGuard)`
2. `services/api_service.dart` call from provider/screen

**New DB column:**
1. `*.entity.ts` @Column → restart backend (auto-sync in dev)
2. Update mapper + frontend model (`fromJson()`, `copyWith()`)

---

## 3. Shared Wire Contracts

**E2E envelope:** `{ content, messageType?, mediaUrl?, mediaDuration?, mediaKey?, mediaIv?, linkPreview? }`. `messageType` defaults `TEXT`. Ciphertext: `"{type}:{base64}"` (3=PreKey, 2=Signal/whisper). `sendMessage` payload includes `messageType`/`mediaUrl`/`mediaDuration` for DB orphan/expiry tracking — server doesn't see plaintext or keys.

**Delete actions:**

| Action | Deletes | Friend? | WS Event |
|---|---|---|---|
| Delete Conversation | Messages + Conversation | Kept | `deleteConversationOnly` |
| Unfriend | FriendRequest + Conv + Messages | Removed | `unfriend` |
| Clear History | Messages only | Kept | `clearChatHistory` |
| Delete for me | Hidden for user | Kept | `deleteMessage` mode=for_me |
| Delete for everyone | Hard-delete both; clears pin | Kept | `deleteMessage` mode=for_everyone |

**Edit message** (text only, sender-only, 15-min window): WS `editMessage` `{ messageId, content:'[encrypted]', encryptedContent }` — a NEW ciphertext over the existing Signal session (server stays blind). Server (`handleEditMessage`) replaces stored `encryptedContent`, stamps `editedAt`, leaves `expiresAt`/`disappearAfterSeconds`/`deliveryStatus` untouched → broadcasts `messageEdited` `{ messageId, conversationId, content, encryptedContent, editedAt }` to both; rejects (not sender / past window / not found) via `editMessageFailed` `{ messageId, reason }` to the editor only. Replace-in-place (no edit history). Prod SQL: `ALTER TABLE messages ADD COLUMN "editedAt" timestamp NULL;`

**Frontend reactions/emoji UX:** long-press reaction UI is frontend-only on the existing `addReaction`/`removeReaction` socket contract (`{messageId, emoji}`). The composer and reaction sheet use `emoji_picker_flutter`; text insertion/backspace must stay grapheme-safe via `characters`, not UTF-16 slicing.

---

## 4. Environment & Config

| Variable | Required | Purpose |
|---|---|---|
| `DB_HOST/PORT/USER/PASS/NAME` | Yes | PostgreSQL |
| `JWT_SECRET` | Yes | JWT signing (≥32 chars prod) |
| `MEDIA_BASE_URL` | No | Public base URL for media (default `http://localhost:3000`) |
| `MEDIA_DIR` | No | Filesystem root for media (default `/app/media`) |
| `MEDIA_CLEANUP_GRACE_MS` | No | Cron grace window — never delete msgs blobs newer than this (default 900000 = 15 min) |
| `FIREBASE_SERVICE_ACCOUNT` | No | FCM push |
| `WEB_PUSH_VAPID_PUBLIC_KEY` | No | VAPID public key |
| `WEB_PUSH_VAPID_PRIVATE_KEY` | No | VAPID private key |
| `WEB_PUSH_VAPID_SUBJECT` | No | VAPID subject (`mailto:` or URL) |
| `ALLOWED_ORIGINS` | No | CORS comma-separated |
| `BASE_URL` | No | Frontend dart define (default `http://{host}:3000`) |
| `GIPHY_API_KEY` | No | Frontend dart define |
| `GIT_COMMIT` | No | Short SHA; local default `dev` |
| `BUILD_TIME` | No | UTC ISO timestamp |
| `APP_VERSION` | No | Semver from pubspec; fallback `0.0.2` |

**Docker:** `db` postgres:16-alpine (5433→5432), `backend` node:20-alpine (:3000), volume `media_storage` → `/app/media`. `frontend/nginx.conf` proxies `/media/*`, `/health`, `/version` (exact match).
**Push:** VAPID keys must match frontend dart-define and backend env — mismatch → `Registration failed`. iOS web push requires outbound to `*.push.apple.com`. `deploy.sh` loads `WEB_PUSH_VAPID_PUBLIC_KEY` from repo `.env`.

---

**Maintain this file.** Update the relevant section after every code change; tier-specific gotchas go in `backend/CLAUDE.md` / `frontend/CLAUDE.md`. Update the backend test count after adding/removing tests; ensure `node scripts/verify-claude-backend-test-counts.mjs` passes.
