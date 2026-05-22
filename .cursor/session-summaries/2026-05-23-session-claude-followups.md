# Session summary — 2026-05-23

## Accomplished

- **CLAUDE.md follow-ups** from claude-md-improver audit:
  - Extracted §1 gotchas to **`docs/AGENT-GOTCHAS.md`** (~140 lines); `CLAUDE.md` §1 is now a short pointer (~7 lines). Main doc ~351 lines (was ~485).
  - **UTF-8:** added root **`.editorconfig`** (`charset = utf-8` for `*.md`, `CLAUDE.md`); encoding note in both agent docs.
  - **Version align:** `frontend/pubspec.yaml` **0.0.2** (matches `settings_screen_version_footer_test.dart`); `docker-compose` `APP_VERSION` default `0.0.2`; backend `version.controller` fallback `0.0.2`.
  - **CI drift guard:** `scripts/verify-claude-backend-test-counts.mjs` + backend job step after `npm test` (parses Jest summary vs `CLAUDE.md` Tests line).
  - Updated `.cursor/rules/On-every-check.mdc`, `.kiro/steering/verification-discipline.md`, `CLAUDE.md` maintain note.

## Key files

- `docs/AGENT-GOTCHAS.md` (new)
- `CLAUDE.md`, `.editorconfig`, `scripts/verify-claude-backend-test-counts.mjs`, `.github/workflows/ci.yml`
- `frontend/pubspec.yaml`, `docker-compose.yml`, `backend/src/version/version.controller.ts`

## Notes for next session

- **Commit** not done — user can commit doc + version `0.0.2` when ready.
- **Deploy:** production still shows old version until VM `deploy.sh` with updated pubspec.
- Re-run `node scripts/verify-claude-backend-test-counts.mjs` after backend test count changes.
