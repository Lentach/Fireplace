# Workflow 2.0 audit — measured the agent workflow, proposed the cut

**Date:** 2026-09-10 · **Version:** 0.2.36 → unchanged · **Tiers deployed:** none (repo hygiene + docs; no app code)

## What was done

- Measured the always-on context floor: a frontend session loads **~55k tokens** of instruction files before any code (`CLAUDE.md` 13k of which §7 wire contracts = 8.1k / 62%; `frontend/CLAUDE.md` 21k of which §5 E2E 6.6k + §10 passcode 5.9k + §7 composer 3k; `LATEST.md` 9.2k of which the rotated-out banner ≈ 2.5k).
- Measured usage across the 100 sessions since the 2026-07-27 tooling audit, **paired with hard signals** because mention-counts measure narration (gitleaks: 1 mention, runs on every commit via `.githooks/pre-commit:16`): Dart MCP **0 agent calls** but the mount **works** (this session: `roots add` + `analyze_files lib/main.dart` → "No errors"; binary is pub-cache `dart_mcp_server.bat` 1.1.0, SDK-bundled `dart mcp-server` is 0.1.4); `impact.mjs` 1 (CI self-test only); graphify: hook executes, output read 0; context7 1 (Claude-Code plugin, not mounted in OMP); skills 2 (OMP mounts 18 of the 37 `~/.claude/skills` dirs; plugins cost 0 OMP tokens). Pulling weight: lint-ratchet 51, smoke 47, verifiers 28, CDP drive 16, mutants 8.
- Measured commit mix since 2026-07-28: 587 commits, **225 `docs` (38%)**, **289 touching `.cursor/session-summaries/` (49%)**; last 12 dated summaries average 11 KB.
- Found the July cull list was never executed; found every model role in `~/.omp/agent/config.yml` is Opus (`smol`/`tiny`/`task` included); found `frontend/CLAUDE.md:225` never names the Dart MCP (Flutter 3.44.6, `sdk: ^3.10.7` is a floor — agentic hot reload needs no bump).
- Web check of 2026 guidance: ≤250-line always-on file, every rule falsifiable + enforced-or-tagged-advisory, hooks/skills/subagents split, one-MCP-is-fine for a two-language solo stack.
- Wrote **`docs/agents/workflow-2.0.md`**: verdict, two-signal measurements, delete list (per-harness cost stated separately), context-budget redesign (root §7 → `docs/contracts/wire.md` behind a glob rule; frontend §5/§7/§10 → `frontend/docs/*.md`; target floor 55k → ~17k), handoff ritual 2.0 (`docs/agents/traps.md` + ≤6 KB templated summary + ≤900-char LATEST entries), Dart MCP on a **hard 30-session probation** after routing (honouring the July audit's own exit criterion), **one** new skill (`umbra-session-end`, hook-enforced; four others deferred as doc sections), model-role split (Opus 5 for reasoning roles, Haiku for `smol`/`tiny`), `scripts/verify-context-budget.mjs` in pre-commit, 6 reversible batches.

- **Applied ("yes remove and do 3 small ones"):** graphify removed (Dart edges 1.8% precision), `gitleaks git --staged`, CI check = check-runs API, `.planning/` root tidied — proof table in `docs/agents/workflow-2.0.md` §7.
- **Wall of text removed (batches 3–5):** root §7 → `docs/contracts/wire.md`; frontend §5/§7/§10 → `frontend/docs/*.md`; all md5-verified byte-identical; 4 `.cursor/rules/*.mdc`; LATEST banner → `docs/agents/traps.md`; root §1 rewritten; `scripts/verify-context-budget.mjs` in pre-commit. **Floor: always-on 6.6k tokens (was ~27k), frontend session 12.5k (was ~48k).** Mechanics + measurements: `docs/agents/workflow-2.0.md` §3/§7.
- **Owner said "yes on everything" — all applied and committed (`dedb8dd` + this one):** 6 Claude Code plugins uninstalled (`ralph-loop`, `skill-creator`, `frontend-design`, `code-simplifier`, `playwright`, `context7`); 24 skill junctions removed from `~/.claude/skills/` (12 remain; `qa`/`request-refactor-plan`/`design-an-interface` were never on disk); `@playwright/mcp` dropped from `~/.omp/agent/mcp.json` (now empty — Dart MCP lives in project `.omp/mcp.json`); `config.yml` model roles applied (backup `config.yml.pre-workflow2`); Dart MCP routed into `frontend/CLAUDE.md` §9 with the probation clause + CDP drive recipe; `.omp/skills/umbra-session-end/SKILL.md` written (the hook is its enforcement).

## Key files

- `docs/agents/workflow-2.0.md` (new, the deliverable)
- Edited: `CLAUDE.md` (§1 rewritten for the 2.0 handoff + graphify line removed, §2 rewritten, §3 CI command, §7 → stub), `frontend/CLAUDE.md` (§5/§7/§10 → stubs), `.githooks/pre-commit` (gitleaks form + budget gate)
- New: `docs/contracts/wire.md`, `frontend/docs/*.md` ×3, `.cursor/rules/*.mdc` ×4, `docs/agents/traps.md`, `scripts/verify-context-budget.mjs`, `.githooks/pre-commit`, `.cursor/rules/production-vm-deploy.mdc` (preflight block), `.gitignore`; deleted `.githooks/post-commit`, `.githooks/post-checkout`, `graphify-out/`
- Read only: `frontend/CLAUDE.md`, `.cursor/session-summaries/LATEST.md`, `.planning/tooling-audit/{WORKFLOW,TIER-LIST}.md`, `.omp/mcp.json`, `~/.omp/agent/{config.yml,mcp.json}`, `~/.claude/plugins/installed_plugins.json`, `.githooks/{pre-commit,post-commit}`

## Verification

- Sizes from `wc -c`/`wc -w`; section tokens from a chars/4 split on `## ` headings; usage counts from regex over `.cursor/session-summaries/2026-07-2[89]*..2026-09-*` (100 files); commit mix from `git log --since=2026-07-28`. All reproducible; the script is inline in the session transcript, not committed.
- Gate hole closed after it let an 8.4 KB summary through: size cap now applies to added AND modified summaries, template check to added only, and `--worktree` mode diffs against HEAD; re-proven (modified oversize → exit 1 in both modes).
- Gate proven both ways: `node scripts/verify-context-budget.mjs` → OK on the staged tree; a synthetic 6th LATEST entry → exit 1 with the rotation message; restored → OK. `sh .githooks/pre-commit` on the real index → exit 0.
- No app code changed; no tier tests run. Hook change proven by running the new gitleaks form; CI command proven live; graphify numbers from a script over `graphify-out/graph.json` BEFORE deletion (2,430/1,003/43).

## Notes for next session

- **Owner, a reversal of your 2026-08-14 decision:** per-entry LATEST caps are back (≤900 chars, hook 1000). The 08-14 failure mode (banner counted as an entry → evidence deleted to fit) is gone by construction: no banner, standing facts go to `traps.md` uncapped. Rationale kept in `traps.md § Handoff`.
- **Accuracy audit DONE (owner asked):** six parallel auditors, code-only evidence, one file each — **~574 claims checked, 42 corrected in place**, every correction with file:line (reports: `agent://Audit{Wire,E2E,Composer,Passcode,BackendTier,RootAndFrontendTier}`; digest + the five source-comment rot findings in `docs/agents/workflow-2.0.md` § Accuracy audit). Dead globs in two rules + two stubs replaced with real paths. **Spot-checked 9 of the highest-impact corrections against source myself — all resolve as reported.** Comment-only source fixes applied: stale "72 h" prose → 6 h in `identity-reset.service.ts` (7 sites) + `chat-key-exchange.service.ts` (2); the "Owner decision pending" OTP-ordering note rewritten as settled for the identity-upload path (stash-on-ack, `stale_otp_epoch_test.dart` mirrors it) while naming the two emitters that are NOT races (replenishment; un-enrolled remint carve-out). `git diff --cached -- backend/src` non-comment lines: 0. Test counts / in-doc version dates: not verifiable from source.

- **Nothing owed.** Every batch is applied. Next-session checks: `read rule://wire-contracts` (rules load at startup), and `read skill://umbra-session-end`.
- **Not mine, left unstaged:** one-line edit in `2026-09-09-session-c9-phrase-at-the-door.md` (scanner teardown wording). Commit or drop it deliberately.
- **Trap:** `read` of `LATEST.md` truncates lines at 768 chars — the banner and deploy-state line are far longer than they look; measure with `wc`, not by eye.
