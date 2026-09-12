# Agent harness practice — vendor guidance (2026-09) vs Umbra workflow 2.0

**Date:** 2026-09-10
**Sources:** primary only (vendor docs, vendor engineering posts, the harness's own docs/binary). Every claim below either cites a vendor page or reports a probe run on this machine.
**Measured:** 2026-09-12 on the dev box — `omp` **18.1.18**, repo at `C:/Users/Lentach/Desktop/fireplace`. Probe commands and raw outputs are in §8 so any claim can be re-run.

## 0. Verdict

Workflow 2.0's *direction* is exactly what the vendors now publish: keep one small always-on file, push everything else behind a trigger, and put an enforcement layer under any rule that matters ([Anthropic, *Effective context engineering*](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents); [Claude Code *Best practices*](https://code.claude.com/docs/en/best-practices)).

Its *mechanism* is mis-wired for the harness that actually runs it. Three measured facts:

1. **In OMP, root `CLAUDE.md` is not loaded at all.** At depth 0 the `agents-md` provider shadows `claude-md`, so the only injected project context file is `AGENTS.md` (1,275 B of pointers). The 24 KB cap in `scripts/verify-context-budget.mjs` governs a file OMP never injects (§2, probe P1).
2. **The four glob-scoped `.cursor/rules/*.mdc` entries disappear in subagents.** The main session lists all five rules in `<domain-rules>`; two independent subagent sessions list only `production-vm-deploy` (the one rule *without* `globs`), and `rule://frontend-e2e-invariants` errors with *Unknown rule* inside a subagent. Subagents are where this repo does most edits — the 2026-09-10 accuracy audit ran six of them (§3, probes P2/P3/P4).
3. **The comma-separated `globs:` strings are a dead gate in OMP.** OMP wraps a string `globs` value into a single-element array without splitting on commas, so `globs: a/**,b/**` matches no path. Proven by differential test: a single-glob rule fires, the comma-joined one never does (§3, probe P5). Cursor *does* document comma-separated globs, so the same line is correct for Cursor and inert for OMP.

There is a documented OMP mechanism that does exactly what §3a wanted — `condition:` with a file glob compiles to a `tool:edit(...)`/`tool:write(...)` path gate that injects the rule body when an edit touches a matching file, and it survives into subagents (probe P6). The repo does not use it.

## 1. What the repo ships today (measured)

| Artifact | Size | Loaded when |
|---|---|---|
| `AGENTS.md` | 1,275 B / 20 lines | **OMP: every request** (only injected project context file, probe P1) |
| `CLAUDE.md` | 20,387 B / 130 lines, longest line 957 chars | **Claude Code: every session** ([memory docs](https://code.claude.com/docs/en/memory)); **OMP: never auto-injected** — read on demand because `AGENTS.md` says to |
| `frontend/CLAUDE.md` | 25,014 B / 180 lines, longest line 1,234 chars | read once per frontend session (by instruction, not by loader) |
| `backend/CLAUDE.md` | 21,232 B / 163 lines | same |
| `docs/contracts/wire.md` | 35,561 B | behind `.cursor/rules/wire-contracts.mdc` |
| `frontend/docs/{e2e-invariants,composer-media,passcode-lock}.md` | — | behind three `.cursor/rules/*.mdc` |
| `docs/agents/traps.md` | 10,795 B / 74 lines | nothing loads or points to it except root `CLAUDE.md` §1 — `AGENTS.md` never names it |
| `.cursor/session-summaries/LATEST.md` | 5,365 B / 15 lines | session start (by instruction) |
| `.omp/skills/umbra-session-end/SKILL.md` | 3,361 B | OMP only (`.omp/skills` is not a Claude Code location) |
| `.githooks/pre-commit` + `scripts/verify-context-budget.mjs` | caps: root 24,000 B, tier 28,000/26,000 B, LATEST 10,000 B / 5 entries / 1,000 chars, new summary 8,000 B + four required headings | every `git commit` |

Two internal inconsistencies, both harmless but both real: workflow 2.0 §6 tables a **16,000 B** root cap while the shipped verifier uses **24,000** (`scripts/verify-context-budget.mjs:16`); and §4 specifies the summary headings `## Done / ## Proof / ## Open / ## Traps` while the verifier and the `umbra-session-end` skill enforce `## What was done / ## Key files / ## Verification / ## Notes for next session` (`scripts/verify-context-budget.mjs:24`).

Root `CLAUDE.md` also opens with `---\ndescription:\nalwaysApply: true\n---`. No vendor documents frontmatter on a root `CLAUDE.md`: Cursor's `alwaysApply` is a `.cursor/rules/*.mdc` field ([Cursor rules](https://cursor.com/docs/rules)), Claude Code documents no frontmatter for `CLAUDE.md` ([memory docs](https://code.claude.com/docs/en/memory)), and OMP classifies a standalone `CLAUDE.md` as a *context file* via the `claude-md` provider, not as a rule ([`omp://context-files.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/context-files.md)) — confirmed by probe P3, where no rule named `CLAUDE` exists. The block is inert text.

## 2. Q1 — instruction-file size: what the vendors say, and does 24 KB match?

| Vendor | Documented limit | Page |
|---|---|---|
| Claude Code | "**target under 200 lines** per CLAUDE.md file. Longer files consume more context and reduce adherence." Files over **4 MiB** are skipped entirely. | [memory](https://code.claude.com/docs/en/memory) |
| Claude Code | "Bloated CLAUDE.md files cause Claude to ignore your actual instructions." Per line: *"Would removing this cause Claude to make mistakes?"* If not, cut it. | [best practices](https://code.claude.com/docs/en/best-practices) |
| Claude Code auto memory | index `MEMORY.md` loads **first 200 lines or 25 KB, whichever comes first**; past that is silently dropped, and the client *errors* telling Claude to rewrite the index | [memory](https://code.claude.com/docs/en/memory) |
| Cursor | "Keep rules **under 500 lines**. Split large rules into multiple, composable rules." | [rules](https://cursor.com/docs/rules) |
| GitHub Copilot | its own onboarding prompt constrains generated `copilot-instructions.md` to "**no longer than 2 pages**" and "must not be task specific" | [repo custom instructions](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions) |
| Anthropic (engineering) | "find the **smallest possible set of high-signal tokens** that maximize the likelihood of some desired outcome"; context rot is a measured performance gradient, not a cliff | [context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) |
| OMP | no numeric cap published; guidance is structural — "Keep `RULES.md` short. Long background belongs in `AGENTS.md`, where it costs context budget only once." | [`omp://context-files.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/context-files.md) |

**Does 24 KB match?** Partly, and the unit is better than the vendors'.

- Nobody publishes a byte cap for the *authored* instruction file; the only vendor byte number is the 25 KB / 200-line limit on Claude's **auto-memory index**. 24 KB sits just under that, which is a defensible ceiling by analogy but not a citation.
- Bytes beat lines for this repo. Root `CLAUDE.md` is **130 lines** — comfortably inside Claude's 200-line target — while being 20 KB with 957-char lines. A line cap would pass a file that costs ~5.1k tokens. Workflow 2.0 §1a already spotted this ("170 lines but 52 KB because lines are 800-char paragraphs"); keeping the cap in bytes is the right call.
- But 24 KB is ~2× the *spirit* of "under 200 lines" and 45% above §3a's own stated target of ≤3,500 tokens (≈14 KB). The cap was set to the post-migration size (20.6 KB) plus slack, so it can only bite on regrowth — correct ratchet semantics, wrong number relative to the goal the document states.
- The tier caps (28 KB / 26 KB) have no vendor analogue at all, because no vendor has a "tier file you read once by instruction" concept. Under Claude Code these files are *not* auto-loaded from the root session either (Claude loads subdirectory `CLAUDE.md` only "when Claude reads files in those directories" — [memory docs](https://code.claude.com/docs/en/memory)), so their real cost is a deliberate `read`, which is what §3b assumed. That part is sound.

## 3. Q2 — glob-triggered rules: who actually honours `globs`?

| Harness | Reads `.cursor/rules/*.mdc`? | Does `globs` auto-load the rule? | Evidence |
|---|---|---|---|
| **Cursor** | yes, `.mdc` only (a plain `.md` in `.cursor/rules` is **ignored**) | **Yes.** `alwaysApply: false` + `globs` provided ⇒ "Auto-attached when a matching file is in context". Comma-separated patterns are documented. | [Cursor rules](https://cursor.com/docs/rules) |
| **OMP** | yes, `cursor` rule provider, priority 50, `<cwd>/.cursor/rules/*.{mdc,md}` | **No.** A rule with `description` and no `condition`/`astCondition` lands in the **rulebook** bucket: name + globs + description listed in the prompt, body read on demand via `rule://`. The docs are explicit: *"`globs` … is not used to automatically select rulebook rules"*, and *"code does not enforce glob applicability"*. `globs` is a hard gate **only** for TTSR rules. | [`omp://rulebook-matching-pipeline.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/rulebook-matching-pipeline.md) §6, §7 |
| **OMP subagents** | rules are re-bucketed per session | **Worse than advisory — absent.** Probes P2/P3/P4: the main session's `<domain-rules>` lists all five rules; a `task` subagent and a `sonic` subagent each list only `production-vm-deploy`, and `rule://frontend-e2e-invariants` returns *Unknown rule*. Built-in TTSR rules (`ts-no-any`, `go-*`, `rs-*`) **are** present in the same subagent, so TTSR crosses the boundary and glob-scoped rulebook entries do not. Cause not published; treat as harness behaviour, not as documented contract. `[INFERENCE]` on cause, measured on effect. | probes P2–P4 |
| **Claude Code** | **not at runtime.** `/init` reads `.cursor/rules` / `.cursorrules` once and folds relevant parts into the generated `CLAUDE.md`; `/import` copies config in. Its own path-scoped mechanism is `.claude/rules/*.md` with `paths:` frontmatter. | n/a for `.cursor/rules`; **yes** for `.claude/rules` `paths:` — "Path-scoped rules trigger when Claude reads files matching the pattern". | [memory](https://code.claude.com/docs/en/memory) |
| **Copilot / VS Code** | no | n/a; its mechanism is `.github/instructions/**/*.instructions.md` with `applyTo` globs (comma-separated supported) | [GitHub docs](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions) |

**Is the repo's reliance on `globs` sound?** For Cursor, yes. For OMP — the primary harness — no, on two counts: the glob is advisory in the main session and the rule is missing entirely in subagents; and the comma-joined glob string never matches a path even where globs *are* enforced (probe P5: `globs: aaa/**,bbb/**` does not fire on `bbb/x.ts`; `globs: bbb/**` does; `globs: [aaa/**, bbb/**]` does). For Claude Code, the rules are invisible except through `/init`. So of the four harnesses the repo nominally targets, exactly one implements the intended behaviour.

What still works in OMP's favour: the rulebook listing *is* in the main-session system prompt with the globs rendered inline, and the main agent is reliably the one that reads `docs/contracts/wire.md`. The failure mode is narrow and specific — delegated edits.

## 4. Q3 — is there a documented cross-harness "load on file match" that beats `.cursor/rules`?

There is no single file that every harness path-triggers. There are four documented mechanisms, and one of them is strictly stronger than what the repo uses.

| Mechanism | Honoured by | Trigger semantics | Verdict for this repo |
|---|---|---|---|
| `.cursor/rules/*.mdc` + `globs` | Cursor (auto-attach), OMP (advisory rulebook), Claude Code (`/init` only) | file in context | keep as the Cursor/OMP-main surface; insufficient alone |
| **OMP `condition:` with a file glob** (in `.omp/rules/*.md` or in the same `.mdc`) | OMP only | the glob is rewritten to `tool:edit(<glob>)` + `tool:write(<glob>)` scope with catch-all regex `.*`, so the rule body is injected as a `<system-interrupt>`/`<system-reminder>` **at the moment an edit or write touches a matching path** — and TTSR rules are registered per session including subagents | **strongest available.** Probe P6: `condition: frontend/lib/**/passcode*` fires on an edit to `frontend/lib/screens/passcode_screen.dart` and does not fire on `backend/src/app.ts`. Documented in [`omp://rulebook-matching-pipeline.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/rulebook-matching-pipeline.md) §2 ("condition values that look like file globs are converted into `tool:edit(...)`/`tool:write(...)` scope shorthands with catch-all condition `.*`") and [`omp://ttsr-injection-lifecycle.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/ttsr-injection-lifecycle.md) |
| `.claude/rules/*.md` + `paths:` | Claude Code | loads when Claude **reads** a matching file; survives compaction by reloading on next match | the only documented Claude Code path-scoping. Not an OMP rule provider (OMP's `claude` provider contributes `.claude/CLAUDE.md` context and `.claude/skills`, not `.claude/rules`), so adding it costs Claude Code correctness and nothing in OMP |
| `.github/instructions/*.instructions.md` + `applyTo` | Copilot cloud agent + Copilot code review (path-scoped support is limited to those on github.com), VS Code, and OMP as a rule provider (priority 30) | glob on the file under work | in OMP this lands in the **same advisory rulebook bucket** unless `applyTo` is `*`/`**`/`**/*`, in which case it becomes always-apply and is injected in full. So it is *not* an upgrade over `.cursor/rules` for OMP; it is the right file only if Copilot review is wanted |

Practical shape, all vendor-documented: keep one canonical area doc (`docs/contracts/wire.md` etc.), and keep the *trigger* duplicated as a 3-line stub per harness — `.cursor/rules/x.mdc` (globs, for Cursor + OMP listing), `.omp/rules/x.md` (`condition:` glob, for OMP enforcement incl. subagents), `.claude/rules/x.md` (`paths:`, for Claude Code). OMP dedups rules **by name, first-wins by provider priority** (`native` 100 > `cursor` 50 > `github` 30), so same-named stubs are safe: the native `.omp/rules` copy wins in OMP and the others stay live in their own harness ([`omp://rulebook-matching-pipeline.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/rulebook-matching-pipeline.md) §4). Name them identically on purpose.

One more OMP-native lever the repo has not used: **`.omp/RULES.md`** is loaded as an always-apply rule that is "re-attached near the current turn, so it keeps its hold even after the visible conversation grows" — the documented home for "the handful of hard requirements" ([`omp://context-files.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/context-files.md)). That is precisely what root `CLAUDE.md` §1 is trying to be, and it is currently not loaded in OMP at all.

## 5. Q4 — memory: OMP's built-ins vs `traps.md` + `LATEST.md`

What the vendors endorse as a *pattern* is what the repo already does. Anthropic calls it **structured note-taking**: "the agent regularly writes notes persisted to memory outside of the context window … like your custom agent maintaining a NOTES.md file … this simple pattern allows the agent to track progress across complex tasks" ([context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)). `traps.md` (permanent, one line each) + `LATEST.md` (5 entries, capped) + dated summaries is a three-lifetime version of that, with a hook enforcing the caps. Claude Code's own auto memory uses the same shape — a one-line-per-entry `MEMORY.md` index loaded every session, with detail in topic files read on demand ([memory](https://code.claude.com/docs/en/memory)).

What OMP offers instead:

| Feature | What it is | Cost / reach | Verdict here |
|---|---|---|---|
| `memory.backend: local` | background pipeline: per-session extraction then consolidation into `MEMORY.md`, `memory_summary.md`, generated `skills/`; the summary is injected at session start under `memories.summaryInjectionTokenLimit` (default **5,000 tokens**) | extraction runs on the **`default` role** (here `claude-fable-5-1:high`), consolidation on `smol`; **skipped for subagents**; artifacts live in `~/.omp/agent/memories/<encoded-cwd>/` — machine-local, not in the repo | **do not adopt.** It buys an auto-written 5k-token block that duplicates `traps.md`, priced at a model pass over past sessions on every startup, and it is invisible to Claude Code, to the public repo, and to every subagent. Currently **off** (`~/.omp/agent/config.yml` has no `memory` or `autolearn` key — measured) |
| `learn` tool | writes one durable lesson to `learned.md` (≤100 bullets, ≤2,000 chars each, newest-first, deduped, secret-redacted), optionally creating/updating a **managed skill** | requires `autolearn.enabled` **and** a memory backend; **subagents do not receive it**; managed skills land in `~/.omp/agent/managed-skills/`, never in the repo | **no.** `traps.md` is the same artifact, one line per trap, in git, reviewable in a PR, and greppable by every harness. `learn` would put the repo's institutional memory on one Windows box |
| managed skills (`omp-managed`, priority 5) | auto-written `SKILL.md`s that always defer to authored skills | machine-local | no; authored `.omp/skills`/`.claude/skills` already win by precedence |
| `memory://` URLs | read the above artifacts | — | nothing to read while the backend is off |

Sources: [`omp://memory.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/memory.md), [`omp://tools/learn.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/tools/learn.md), [`omp://skills.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md).

**Should the repo use them? No — with one exception.** The repo's convention is *better* on every axis that matters for a solo-maintained public repo: it is committed, diffable, cross-harness, and hook-enforced. The exception is reach: `traps.md` is only useful if something tells the agent to grep it, and the one file OMP always injects (`AGENTS.md`) does not mention it. That is a one-line fix, not a reason to import a memory backend.

Two related skill facts worth recording: the `umbra-session-end` skill lives in `.omp/skills/`, which is OMP-native only — Claude Code reads `.claude/skills/` ([best practices](https://code.claude.com/docs/en/best-practices)), and OMP *also* reads project `.claude/skills` via its `claude` provider at priority 80 ([`omp://skills.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md)). One file in `.claude/skills/umbra-session-end/SKILL.md` would serve both harnesses. And Anthropic's skills guidance backs §5b's "ship a skill only when a session reaches for it": "Start with evaluation: identify specific gaps … then build skills incrementally to address these shortcomings" ([agent skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills), which also notes Skills were published as an open standard on 2025-12-18).

## 6. Q5 — hooks as enforcement: can one replace the git pre-commit gate?

Both harnesses agree with the workflow doc's thesis ("a rule without one is a wish"). Claude Code states it twice: instructions are "context, not enforced configuration. To block an action regardless of what Claude decides, use a PreToolUse hook instead" ([memory](https://code.claude.com/docs/en/memory)); "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens" ([best practices](https://code.claude.com/docs/en/best-practices)).

| Capability | Claude Code | OMP |
|---|---|---|
| Pre-tool block | `PreToolUse` with `matcher` + optional `if` (e.g. `Bash(rm *)`), returning `permissionDecision: "deny"`; configured in `.claude/settings.json`, plugins, skill/subagent frontmatter; **also fires inside subagents** | `tool_call` event handler returning `{ block: true, reason }` — "if handler throws, wrapper fails closed and blocks execution" |
| Post-tool | `PostToolUse` / `PostToolUseFailure` / `PostToolBatch` | `tool_result` (can rewrite content/details) |
| End-of-turn gate | `Stop` with `decision: "block"` + `reason` (or `additionalContext`); **Claude Code overrides the hook and ends the turn after 8 consecutive blocks** | `turn_end` / `agent_end` / `session_shutdown` events, plus TTSR as the mid-stream corrective |
| Mid-stream correction | — | **TTSR**: regex/ast match aborts the stream, injects the rule, retries from the same point; "you get course-correction without paying context tax on every turn" |
| Handler type | shell command, HTTP endpoint, MCP tool, prompt, or subagent; Windows example is `powershell.exe -NoProfile -File …` | default-exporting **TS/JS module** (`.omp/hooks/pre/*.ts`), loaded in-process by the extension runner |
| Config surface | `~/.claude/settings.json`, `.claude/settings.json(.local)`, managed policy, plugin `hooks/hooks.json` | `.omp/hooks/…` discovery, `--hook`/`-e` paths, plugins |

Sources: [Claude Code hooks reference](https://code.claude.com/docs/en/hooks), [`omp://hooks.md`](https://github.com/can1357/oh-my-pi/blob/main/docs/hooks.md), [oh-my-pi README §04](https://github.com/can1357/oh-my-pi#readme).

**Could a hook replace `.githooks/pre-commit`? No.** Three reasons, all structural:

1. **Scope.** A harness hook fires only inside that harness. The gate has to hold for a commit made by Claude Code, by `omp`, by Cursor, by the git UI, and by the owner typing `git commit` — only a git hook covers all five. The repo is public and solo-maintained; the gate is the last line before a push.
2. **Duplication.** Enforcing the same caps in two harnesses means two implementations of `verify-context-budget.mjs`'s semantics drifting apart. The current design — one Node script, called by git, callable by hand with `--worktree` — is one implementation.
3. **The `Stop` escape hatch.** Claude Code ends the turn after 8 consecutive `Stop` blocks, by design. A gate that gives up after 8 tries is not a gate.

**What hooks *are* worth adding** (complement, not replacement): a `PreToolUse`/`tool_call` deny for the two commands the docs say never to run — `git commit --no-verify` (bypasses the gate) and `gh run list --branch master` (root `CLAUDE.md` §3 says use `gh api …/check-runs` instead). In OMP that is a ~15-line `.omp/hooks/pre/guard.ts` running in-process, which also dodges the Windows constraint that `hub start` cannot spawn `.bat` files — OMP hooks are TS modules, not spawned shells. In Claude Code it is a `.claude/settings.json` `PreToolUse` entry with `matcher: "Bash"`; note `permissions.deny` in managed/project settings is the lighter option for pure command blocking ([memory](https://code.claude.com/docs/en/memory), managed-settings table). A `Stop`-style hook running the budget verifier is redundant with the git hook and should be skipped.

## 7. Repo practice vs vendor guidance vs gap

| Repo practice (workflow 2.0) | Vendor guidance | Gap |
|---|---|---|
| Root `CLAUDE.md` capped at 24 KB, "loaded every request" | Claude Code: <200 lines, prune with *"would removing this cause a mistake?"*; auto-memory index 200 lines / 25 KB | **Cap governs the wrong harness.** In OMP only `AGENTS.md` loads (P1). In Claude Code the cap is real but 24 KB ≈ 5.1k tokens is ~2× the published spirit and 45% over §3a's own ≤3,500-token target. §6 says 16,000; code says 24,000 |
| `AGENTS.md` = 20-line pointer file | agents.md: "a dedicated, predictable place to provide the context"; 60k+ repos; nearest file wins; OMP: highest-priority context file at depth 0 wins the scope | **The one always-on file in OMP carries no rules.** It never names `docs/agents/traps.md`, the four area docs, the glob rules, or the pre-commit gate |
| Area docs behind `.cursor/rules/*.mdc` `globs` | Cursor: globs auto-attach. OMP: globs advisory, "code does not enforce glob applicability". Claude Code: `.claude/rules` `paths:`. Copilot: `applyTo` | **Auto-attach exists only in Cursor.** In OMP-main it is a prompt line; in OMP subagents the rule is absent (P2–P4); in Claude Code it is invisible outside `/init` |
| `globs: a/**,b/**` comma strings | Cursor documents comma-separated globs | **Dead in OMP**: string globs are not split (P5). Fine in Cursor. YAML array form works in both |
| No `condition:`/TTSR rules | OMP: `condition:` file-glob ⇒ `tool:edit/write` path gate, body injected at edit time; README §04 sells this as the no-context-tax mechanism | **Unused.** This is the only mechanism that reaches subagents (P6) |
| No `.omp/RULES.md` | OMP: sticky always-apply rule "re-attached near the current turn", for "the handful of hard requirements" | **Unused.** Root §1's non-negotiables have no sticky home in the primary harness |
| `traps.md` + `LATEST.md` + capped dated summaries | Anthropic: structured note-taking / agentic memory; Claude auto-memory = one-line index + topic files | **Practice matches vendor pattern and beats OMP's built-ins** for a public solo repo (git-visible, cross-harness). Only gap is discovery: nothing auto-points at `traps.md` |
| OMP local memory / `learn` / managed skills not used | OMP: available, project-scoped, `off` by default | **Correct call, undocumented.** Worth writing down *why* (machine-local, Opus-priced extraction, skipped for subagents) so it is not revisited every audit |
| `umbra-session-end` in `.omp/skills/` | Claude Code reads `.claude/skills/`; OMP reads project `.claude/skills` too (priority 80) | **Skill is OMP-only**; `.claude/skills/` would cover both with one file |
| Enforcement = git `pre-commit` (gitleaks + budget verifier) | Claude Code: hooks are the deterministic layer; instructions are advisory | **No gap — this is stronger than the vendor pattern.** Harness hooks fire per harness; a git hook covers every writer. Missing only the cheap complements (`--no-verify`, `gh run list` denials) |
| Skills ship only with mechanical enforcement (§5b) | Anthropic: "Start with evaluation … build skills incrementally to address these shortcomings" | none |
| §4 summary template `Done/Proof/Open/Traps` | — | **Doc/code drift**: verifier + skill enforce `What was done / Key files / Verification / Notes for next session` |

## 8. Probes (re-runnable)

| # | Command (cwd = repo root) | Result |
|---|---|---|
| P1 | `omp -p --model claude-haiku-4-5 --no-session "Do not use tools. List ONLY the file paths that appear in <file path=...> elements of your repo-rules/project-instructions context block"` | `C:\Users\Lentach\Desktop\fireplace\AGENTS.md` — and nothing else |
| P2 | same shape, asking for the verbatim `<domain-rules>` lines | all five `.cursor/rules` entries, each rendered `- <name> (<globs>): <description>` |
| P3 | `read rule://frontend-e2e-invariants` from inside a `task` subagent | `Unknown rule: frontend-e2e-invariants` — available list = `production-vm-deploy` + 27 `builtin-defaults` TTSR rules (`ts-no-any`, `go-*`, `rs-*`) |
| P4 | `sonic` subagent asked for its `<domain-rules>` block | only `production-vm-deploy`; `skillCount` 18 |
| P5 | `omp ttsr test -r <tmp>/globtest.md --source tool --tool edit --path bbb/x.ts 'FIREPLACE_PROBE_TOKEN here' --json` with `globs: aaa/**,bbb/**` vs `globs: bbb/**` vs `globs: [aaa/**, bbb/**]` | comma string: `triggered: []` for both `bbb/x.ts` and `aaa/x.ts`; single glob: triggered; YAML array: triggered |
| P6 | same, rule `condition: frontend/lib/**/passcode*` (no regex) | triggered on `--path frontend/lib/screens/passcode_screen.dart`, not triggered on `--path backend/src/app.ts`; matched regex reported as `.*` |
| P7 | `omp ttsr list --json` | 27 rules, every one from `builtin-defaults`; no project rule appears, confirming none of the repo's rules is a TTSR rule |
| P8 | temp git repo outside the workspace with `.claude/skills/fireplace-probe-skill/SKILL.md`, then `omp -p --model claude-haiku-4-5 --no-session "does your <skills> block list fireplace-probe-skill?"` | `YES` — OMP discovers **project** `.claude/skills`, so one file there serves both harnesses (fix 6) |

P5/P6 rule files were written to the OS temp dir, not the repo. The `globs`-not-split behaviour is also visible in the shipped binary's `discovery/helpers.ts` normaliser, which wraps a string `globs` as `[s.globs]` while `agents`/`scope` go through the CSV parser.

## 9. Gaps in workflow 2.0 — ranked fixes

1. **Make `AGENTS.md` carry the hard rules, because in OMP it is the only file that loads.** Today it is a 20-line pointer and OMP injects nothing else at depth 0 (P1). Add, in ≤40 lines: the non-negotiables from root §1, the names of the four area docs *with their trigger files*, `docs/agents/traps.md` ("grep it for the area you are about to touch"), and the pre-commit gate. Keep it a pointer to `CLAUDE.md` for the rest. Cheapest fix with the largest measured effect.
2. **Add `.omp/rules/*.md` stubs with `condition:` file globs for the four area docs** (same names as the `.cursor/rules` files, so the native copy wins OMP's name-based dedup). This is the only documented mechanism that injects the trigger at edit time and reaches subagents (P6). Three lines of body each — the stub text already exists in the `.mdc` files. Keep the `.mdc` files for Cursor.
3. **Fix the `globs:` lines**: `globs: [backend/src/chat/**, backend/src/**/dto/**, …]` instead of the comma string, in all four `.mdc` files. Correct in Cursor, and the only form OMP can gate on (P5).
4. **Reconcile the byte caps with the doc.** Either lower `BYTE_LIMITS["CLAUDE.md"]` to 16,000 as §6 states (root is 20,387 B today, so this needs ~4.5 KB moved out first — the remaining §1/§6 history paragraphs are the candidates §3a already named), or amend §6 to say 24,000 and explain why. Silent 16 → 24 drift in the enforcement layer is exactly what §6 exists to prevent.
5. **Add `.claude/rules/{wire-contracts,frontend-e2e-invariants,frontend-composer-media,frontend-passcode-lock}.md` with `paths:` frontmatter.** Claude Code is the secondary harness and currently sees none of the four triggers; `.cursor/rules` reaches it only through `/init`. Same 3-line stubs.
6. **Move `umbra-session-end` to `.claude/skills/umbra-session-end/SKILL.md`** (delete the `.omp/skills` copy). OMP discovers project `.claude/skills` at priority 80; Claude Code discovers nothing else. One file, two harnesses.
7. **Create `.omp/RULES.md`** with the 5–8 genuinely non-negotiable lines (never `--no-verify`; never `git revert 0cbf17b`; composer changes need a green repro + owner OK; `gh api …/check-runs`, never `gh run list`; push with the commit). Vendor-documented as re-attached near the current turn, which is the one thing a context file cannot do.
8. **Add the two-command guard hook** — `.omp/hooks/pre/guard.ts` blocking `git commit --no-verify` and `gh run list --branch master`, plus the mirrored `PreToolUse` entry (or `permissions.deny`) in `.claude/settings.json`. In-process TS, so the Windows `.bat` spawn limitation does not apply.
9. **Fix the §4 template text** to the four headings the verifier and skill actually enforce, or change both to §4's. Pick one; two templates in three files is a trap in waiting.
10. **Record the memory decision in §5** (one line): OMP `memory.backend`/`autolearn` stay off — machine-local artifacts, extraction priced at the `default` role, skipped for subagents, invisible to the public repo; `traps.md` + `LATEST.md` is the same vendor-endorsed note-taking pattern with better reach. Prevents a re-litigation each audit.
11. **Drop the "loaded every request" framing for root `CLAUDE.md` in §1a/§3a** and re-state the OMP session floor as measured: `AGENTS.md` (1.3 KB) + rulebook listing + skills/MCP metadata, with root and tier files as *deliberate reads*. The 55k → 17k claim is still directionally right, but the composition is wrong for the harness that does the work.

## Sources

Vendor / primary pages read for this file:

- Claude Code — *How Claude remembers your project* (CLAUDE.md size, `@` imports, hierarchy and load order, `.claude/rules` + `paths:`, auto memory, managed settings vs CLAUDE.md): https://docs.claude.com/en/docs/claude-code/memory → served as https://code.claude.com/docs/en/memory
- Claude Code — *Best practices for agentic coding* (CLAUDE.md pruning test, hooks are deterministic, skills in `.claude/skills/`, verification loops): https://www.anthropic.com/engineering/claude-code-best-practices → served as https://code.claude.com/docs/en/best-practices
- Claude Code — *Hooks reference* (event table, `PreToolUse` `permissionDecision`, `Stop` `decision: block` + 8-block override, hooks fire in subagents, Windows PowerShell handler): https://docs.claude.com/en/docs/claude-code/hooks → served as https://code.claude.com/docs/en/hooks
- Anthropic Engineering — *Effective context engineering for AI agents* (smallest high-signal token set, context rot, just-in-time retrieval, structured note-taking, subagent architectures): https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Anthropic Engineering — *Equipping agents for the real world with Agent Skills* (progressive disclosure, `SKILL.md` metadata pre-loaded, start-with-evaluation guidance, open standard as of 2025-12-18): https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- AGENTS.md — the spec/landing page (format, 60k+ repos, nearest-file-wins, stewarded by the Agentic AI Foundation): https://agents.md/
- Cursor — *Rules* (`.mdc` required, `alwaysApply`/`description`/`globs` interaction table, comma-separated globs, <500-line guidance): https://cursor.com/docs/context/rules → served as https://cursor.com/docs/rules
- GitHub — *Adding repository custom instructions for GitHub Copilot* (`.github/copilot-instructions.md`, `.github/instructions/*.instructions.md` with `applyTo`, `excludeAgent`, AGENTS.md/CLAUDE.md support, 2-page guidance in the generator prompt): https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot → served as https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions
- oh-my-pi — README (TTSR pitch, foreign-format inheritance incl. Cursor MDC and Copilot `applyTo`, memory `retain`/`learn`/`recall`, native Windows): https://raw.githubusercontent.com/can1357/oh-my-pi/main/README.md
- oh-my-pi docs — *Context files* (provider registry and priorities, one-project-file-per-depth shadowing, `@` imports, `RULES.md` stickiness, `.github/instructions` → rules): `omp://context-files.md` = https://github.com/can1357/oh-my-pi/blob/main/docs/context-files.md
- oh-my-pi docs — *Rulebook matching pipeline* (canonical `Rule` shape, bucketing into TTSR/always-apply/rulebook, name-based dedup, `globs` not used to select rulebook rules, `condition`-as-glob shorthand, `agents` scoping): `omp://rulebook-matching-pipeline.md` = https://github.com/can1357/oh-my-pi/blob/main/docs/rulebook-matching-pipeline.md
- oh-my-pi docs — *TTSR injection lifecycle* (registration requirements, glob path gate, interrupt/reminder templates, repeat policy): `omp://ttsr-injection-lifecycle.md` = https://github.com/can1357/oh-my-pi/blob/main/docs/ttsr-injection-lifecycle.md
- oh-my-pi docs — *Hooks* (`tool_call` block semantics, event surfaces, TS factory modules, fail-closed behaviour): `omp://hooks.md` = https://github.com/can1357/oh-my-pi/blob/main/docs/hooks.md
- oh-my-pi docs — *Skills* (layout, frontmatter incl. `globs`/`alwaysApply`/`hide`, provider precedence incl. project `.claude/skills` at 80 and `omp-managed` at 5, `skill://`): `omp://skills.md` = https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md
- oh-my-pi docs — *Autonomous memory* (backends, `local` pipeline phases and model roles, injection token limit, `memory://`, subagent exclusion): `omp://memory.md` = https://github.com/can1357/oh-my-pi/blob/main/docs/memory.md
- oh-my-pi docs — *`learn` tool* (availability gates, `learned.md` caps, managed-skill paths and precedence, subagent exclusion): `omp://tools/learn.md` = https://github.com/can1357/oh-my-pi/blob/main/docs/tools/learn.md

Repo files read (no edits made outside this file): `docs/agents/workflow-2.0.md`, `CLAUDE.md` (head), `AGENTS.md`, `.cursor/rules/*.mdc`, `.omp/mcp.json`, `.omp/skills/umbra-session-end/SKILL.md`, `scripts/verify-context-budget.mjs`, `.githooks/pre-commit`, `docs/agents/traps.md` (head), `~/.omp/agent/config.yml`.
