# Session 2026-07-09 — Agent skills switch: superpowers → mattpocock/skills

## What happened

Owner asked to research "Matt Pocock skills vs superpowers" and, after the comparison, chose a **full switch**.

## Research verdict (for the record)

- **obra/superpowers** (was installed: `superpowers@claude-plugins-official` v5.0.7, user scope) — methodology layer: brainstorm → spec → plan → TDD → subagent dispatch → review. Optimized for long autonomous runs.
- **mattpocock/skills** (github.com/mattpocock/skills, MIT) — ~16 small composable workflow-enforcement skills: `/grill-me`, `/grill-with-docs` (domain glossary + ADRs), `/tdd`, `/diagnosing-bugs`, `/improve-codebase-architecture`, `/to-spec`, `/to-tickets`, `/triage`, `/implement`, `/wayfinder`. Lower ceremony, interactive, model-agnostic.
- Community consensus: different moments, not strict upgrade; **never run both as active routers** (they fight over `/tdd` and routing).

## Changes made

**Machine-level (not in repo):**
- Installed all 38 skills via `npx skills@latest add mattpocock/skills --yes --global` → canonical copies in `~\.agents\skills\`, symlinked into `~\.claude\skills\`.
- Removed 4 repo-deprecated skills (`qa`, `design-an-interface`, `request-refactor-plan`, `ubiquitous-language`) — junction unlink only (`os.rmdir`), canonical copies untouched. 34 active skills remain.
- Uninstalled superpowers: `claude plugin uninstall superpowers@claude-plugins-official` — clean removal, registry verified. Reinstall if ever wanted: `/plugin install superpowers@claude-plugins-official`.

**Repo (this commit) — output of `/setup-matt-pocock-skills` (per-repo config, owner answered all decisions):**
- `docs/agents/issue-tracker.md` — GitHub Issues (`Lentach/Fireplace`) via `gh` CLI; **PRs are NOT a triage surface**.
- `docs/agents/triage-labels.md` — default five: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. Labels not pre-created on GitHub; created lazily on first `/triage` use.
- `docs/agents/domain.md` — **multi-context** consumer rules adapted to the backend/frontend tier split.
- `CONTEXT-MAP.md` (root) — multi-context marker: `backend/CONTEXT.md` + `frontend/CONTEXT.md` (both created **lazily** by `/domain-modeling`; absence is normal), system-wide ADRs in `docs/adr/`.
- `CLAUDE.md` — new `§9 Agent skills` section pointing at the three `docs/agents/*.md` files.

## Notes for future sessions

- Skills that read this config: `to-tickets`, `triage`, `to-spec`, `implement`, `wayfinder` (tracker + labels); `tdd`, `diagnosing-bugs`, `improve-codebase-architecture`, `grill-with-docs` (domain docs).
- Superpowers-named skills (`brainstorming`, `writing-plans`, `subagent-driven-development`, …) no longer exist — use the Pocock equivalents (`grill-with-docs`, `to-spec`/`to-tickets`, `implement`).
- Docs-only change; no version bump (per CLAUDE.md §5). Nothing deployed.
