# Workflow 2.0 audit — measured the agent workflow, proposed the cut

**Date:** 2026-09-10 · **Version:** 0.2.36 → unchanged (docs only) · **Tiers deployed:** none

## What was done

- Measured the always-on context floor: a frontend session loads **~55k tokens** of instruction files before any code (`CLAUDE.md` 13k of which §7 wire contracts = 8.1k / 62%; `frontend/CLAUDE.md` 21k of which §5 E2E 6.6k + §10 passcode 5.9k + §7 composer 3k; `LATEST.md` 9.2k of which the rotated-out banner ≈ 2.5k).
- Measured usage across the 100 sessions since the 2026-07-27 tooling audit, **paired with hard signals** because mention-counts measure narration (gitleaks: 1 mention, runs on every commit via `.githooks/pre-commit:16`): Dart MCP **0 agent calls** but the mount **works** (this session: `roots add` + `analyze_files lib/main.dart` → "No errors"; binary is pub-cache `dart_mcp_server.bat` 1.1.0, SDK-bundled `dart mcp-server` is 0.1.4); `impact.mjs` 1 (CI self-test only); graphify: hook executes, output read 0; context7 1 (Claude-Code plugin, not mounted in OMP); skills 2 (OMP mounts 18 of the 37 `~/.claude/skills` dirs; plugins cost 0 OMP tokens). Pulling weight: lint-ratchet 51, smoke 47, verifiers 28, CDP drive 16, mutants 8.
- Measured commit mix since 2026-07-28: 587 commits, **225 `docs` (38%)**, **289 touching `.cursor/session-summaries/` (49%)**; last 12 dated summaries average 11 KB.
- Found the July cull list was never executed; found every model role in `~/.omp/agent/config.yml` is Opus (`smol`/`tiny`/`task` included); found `frontend/CLAUDE.md:225` never names the Dart MCP (Flutter 3.44.6, `sdk: ^3.10.7` is a floor — agentic hot reload needs no bump).
- Web check of 2026 guidance: ≤250-line always-on file, every rule falsifiable + enforced-or-tagged-advisory, hooks/skills/subagents split, one-MCP-is-fine for a two-language solo stack.
- Wrote **`docs/agents/workflow-2.0.md`**: verdict, two-signal measurements, delete list (per-harness cost stated separately), context-budget redesign (root §7 → `docs/contracts/wire.md` behind a glob rule; frontend §5/§7/§10 → `frontend/docs/*.md`; target floor 55k → ~17k), handoff ritual 2.0 (`docs/agents/traps.md` + ≤6 KB templated summary + ≤900-char LATEST entries), Dart MCP on a **hard 30-session probation** after routing (honouring the July audit's own exit criterion), **one** new skill (`umbra-session-end`, hook-enforced; four others deferred as doc sections), model-role downgrade for scouts, `scripts/verify-context-budget.mjs` in pre-commit, 6 reversible batches.

## Key files

- `docs/agents/workflow-2.0.md` (new, the deliverable)
- Read only: `CLAUDE.md`, `frontend/CLAUDE.md`, `.cursor/session-summaries/LATEST.md`, `.planning/tooling-audit/{WORKFLOW,TIER-LIST}.md`, `.omp/mcp.json`, `~/.omp/agent/{config.yml,mcp.json}`, `~/.claude/plugins/installed_plugins.json`, `.githooks/{pre-commit,post-commit}`

## Verification

- Sizes from `wc -c`/`wc -w`; section tokens from a chars/4 split on `## ` headings; usage counts from regex over `.cursor/session-summaries/2026-07-2[89]*..2026-09-*` (100 files); commit mix from `git log --since=2026-07-28`. All reproducible; the script is inline in the session transcript, not committed.
- No code changed; no tests run (docs only). Nothing applied from the proposal — batches 1–7 await owner OK.

## Notes for next session

- **Owner decisions owed:** (a) execute batch 1 (cull) — zero-regret; (b) batch 3/4 verbatim moves of §7 and frontend §5/§7/§10 — need OK because they change what is auto-loaded; (c) batch 5 edits `.githooks/pre-commit`; (d) batch 6 model roles is a cost/quality call.
- **Not mine, left unstaged:** `2026-09-09-session-c9-phrase-at-the-door.md` carries a one-line uncommitted precision edit (scanner teardown: "tracks stopped, `srcObject` null") that predates this session. Commit or drop it deliberately.
- **Trap:** `git log --format=%s | cut -d: -f1` counts `Merge …` lines as their own type — the 225 `docs` figure is exact, the `Merge` rows were excluded from the percentages.
- **Trap:** `read` of `LATEST.md` truncates lines at 768 chars — the banner and deploy-state line are far longer than they look; measure with `wc`, not by eye.
- Do not re-derive the measurements next session; re-run only after a batch lands, to see the delta.
