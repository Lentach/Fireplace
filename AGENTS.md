# AGENTS.md — Fireplace

Universal agent entrypoint (Codex / Cursor / OMP / any AGENTS.md-reading harness).
**All project knowledge lives in `CLAUDE.md` — this file only tells you to load it.**

## Bootstrap (mandatory, in order)

1. Read root `CLAUDE.md` — workflow rules, architecture, deploy safety, version/env contract, wire contracts.
2. Tier work → read the tier file before your first change there: `backend/CLAUDE.md` (NestJS/Postgres) or `frontend/CLAUDE.md` (Flutter/PWA).
3. Read `.cursor/session-summaries/LATEST.md` for context from previous sessions.
4. Delegating? Tell every subagent to read these files explicitly — subagents do not inherit your context.

## Ground rules (details in `CLAUDE.md` §1)

- Code wins over any doc — when source conflicts with docs, trust source and fix the doc.
- Change only what was asked; read files before editing them; never guess names.
- At task end: write `.cursor/session-summaries/YYYY-MM-DD-session.md` + update `LATEST.md` (format in `CLAUDE.md` §1).
- Production deploy is split and easy to get wrong — `CLAUDE.md` §4 first, full runbook in `.cursor/rules/production-vm-deploy.mdc`.

Maintain this file as a pointer only. New facts go in `CLAUDE.md` or a tier file, never here.
