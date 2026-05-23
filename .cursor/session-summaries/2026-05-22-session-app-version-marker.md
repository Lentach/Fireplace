# Session 2026-05-22 — App version marker

## Accomplished

- **Backend:** `GET /version` (no auth) returns `{ version, gitCommit, buildTime }` from optional env vars; `GET /health` unchanged for Docker healthcheck.
- **Frontend:** Settings footer shows app version (`package_info_plus` + `--dart-define` `GIT_COMMIT` / `BUILD_TIME`). Local dev shows commit `dev` when defines omitted.
- **Deploy:** Added repo-root `deploy.sh` template wiring git SHA and build time into backend Docker args and Flutter web build.
- **Tests:** `version.controller.spec.ts`, `settings_screen_version_footer_test.dart`.
- **Docs:** `CLAUDE.md` updated (deploy, env, Settings, endpoints).

## Key files

- `backend/src/version/*`
- `frontend/lib/config/app_version_info.dart`
- `frontend/lib/screens/settings_screen.dart`
- `deploy.sh`
- `docker-compose.yml`, `backend/Dockerfile`, `frontend/Dockerfile`

## Next session / deploy

- On production VM: merge changes, update `~/deploy.sh` from repo `deploy.sh` (or export `GIT_COMMIT` / `BUILD_TIME` / `APP_VERSION` before backend restart + `flutter build web` with dart-defines).
- Confirm Settings footer and `curl https://fireplace.ignorelist.com/version` match after deploy.
