# CLAUDE.md split rebuild

**Date:** 2026-07-01

## What was done
- Rebuilt the Claude instruction split from the current repository state.
- Used old split commit `4798f9a` and `.cursor/session-summaries/2026-06-21-session-claude-md-split.md` as structure references only.
- Rewrote root `CLAUDE.md` as cross-cutting project memory: workflow, architecture, local commands, production deploy safety, version/env contract, database/E2E safety, shared wire contracts.
- Rewrote `frontend/CLAUDE.md` as Flutter/client memory: commands, provider/service architecture, dart-defines/versioning, PWA/push/cache traps, E2E storage, messaging/UI/composer gotchas, tests/localization.
- Rewrote `backend/CLAUDE.md` as NestJS/server memory: commands, modules, Docker/env, schema rules, auth, Socket.IO, messages/media/push/link-preview/secret-notes contracts.
- Dropped the planned extra review agent after the user asked not to spawn many agents.

## Key files
- `CLAUDE.md`
- `frontend/CLAUDE.md`
- `backend/CLAUDE.md`
- `.planning/2026-07-01-claude-rebuild/task_plan.md`
- `.planning/2026-07-01-claude-rebuild/findings.md`
- `.planning/2026-07-01-claude-rebuild/progress.md`
- `.planning/2026-07-01-claude-rebuild/quality_report.md`

## Verification
- `node scripts/verify-claude-backend-test-counts.mjs` → PASS: `CLAUDE.md` matches Jest output (`328 tests, 41 suites`).
- Python doc content check → PASS after fixing a bad stale-term predicate: required root/frontend/backend facts present; stale false claims absent; line counts `CLAUDE.md` 117, `frontend/CLAUDE.md` 119, `backend/CLAUDE.md` 159.

## Notes for next session
- Docs-only change; no app version bump.
- No `graphify update .` needed because no code files were modified.
- `.tmp/visual-captures/` was already untracked/noisy and was not part of this task.
