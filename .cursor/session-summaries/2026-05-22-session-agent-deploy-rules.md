# Session 2026-05-22 — Agent deploy / version rules

## Accomplished

- Added `.cursor/rules/production-vm-deploy.mdc` — VM paths (`~/fireplace`), full deploy block, version verification, nginx pitfalls.
- Linked `version-bump.mdc` to production deploy rule.
- Updated `CLAUDE.md` Production quick start and `README.md` Deployment section.

## Key files

- `.cursor/rules/production-vm-deploy.mdc` (new)
- `.cursor/rules/version-bump.mdc`
- `CLAUDE.md`, `README.md`

## Notes for next session

- User confirmed prod version visible in Settings; standard deploy is `cd ~/fireplace && ./deploy.sh && cp … frontend-build/`.
