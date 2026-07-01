# Production readiness audit

**Date:** 2026-07-01

## What was done

- Continued on `docs/claude-rebuild` at `8fb8624 chore: prune stale cleanup leftovers`.
- Read repo instructions, tier docs, cursor rules, graph report, prior cleanup archive, and production-readiness planning files.
- Collected current official references for Flutter/Dart, NestJS, TypeORM/PostgreSQL, Socket.IO, Docker/Compose, Web Push/PWA, Apple Web Push, `web-push`, and Firebase FCM.
- Audited frontend, backend, E2E/key-storage, push/PWA, media cleanup, deploy path, scripts/config/docs, and branch state.
- Created visible tracked report: `docs/review/2026-07-01-production-readiness-audit.md`.
- Public read-only production checks found `/health` OK but `/version` still reports stale backend metadata (`0.0.2`, `dev`, empty `buildTime`), and `/version.json` reports frontend `0.0.76` while the audited branch is `0.0.75`.
- Verdict: **NOT READY** for production release sign-off until backend/frontend deploy freshness and live E2E/push/media smoke evidence are proven.
- No application code changed; no version bump; no production deploy; no merge to `master`.
- Code-reviewer was requested before final; it failed with `usage_limit_reached`, so no independent review findings were returned.

## Key files

- `docs/review/2026-07-01-production-readiness-audit.md`
- `.cursor/session-summaries/2026-07-01-session-production-readiness.md`
- `.cursor/session-summaries/LATEST.md`
- `.planning/2026-07-01-production-readiness/task_plan.md`
- `.planning/2026-07-01-production-readiness/findings.md`
- `.planning/2026-07-01-production-readiness/progress.md`

## Verification

- `cd frontend && flutter analyze --no-fatal-infos` — passed, `No issues found!`.
- `cd frontend && flutter test` — passed, `421` tests, `All tests passed!`.
- `cd backend && npm run build` — passed, `nest build` exited 0.
- `cd backend && npm test` — passed, `41` suites and `328` tests.
- `node scripts/verify-claude-backend-test-counts.mjs` — passed, `OK: CLAUDE.md matches Jest (328 tests, 41 suites)`.
- Public read-only checks:
  - `https://fireplace.ignorelist.com/health` — `{ "status": "ok", "db": "ok" }`.
  - `https://fireplace.ignorelist.com/version` — stale/untruthful backend metadata: `0.0.2`, `dev`, empty build time.
  - `https://fireplace.ignorelist.com/version.json` — frontend semver `0.0.76`.

## Notes for next session

- Do not claim production-ready from local tests alone. The release blocker is deploy proof, not a lint failure.
- Before release: merge only with explicit user approval, deploy backend with `./deploy-backend.sh` on the VM, deploy frontend from PC with `.\deploy-web.ps1`, verify public `/version`, `/health`, `/version.json`, and Settings footer commit.
- Run live smoke tests on real PWA/device accounts without clearing site data: login/session refresh, E2E text, encrypted media, push receive/click, destructive media cleanup, and backend logs.
- `graphify update .` was not required because this audit changed docs/session files only.
