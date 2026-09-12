# Claude Code plugins, skills and hooks — September 2026 survey

**Date:** 2026-09-10
**Sources:** primary only

Scope: Claude Code plugins/skills and OMP-compatible skills, ranked against Umbra/Fireplace
(solo maintainer, public repo, E2EE messenger, Flutter 3.44 web+Android, NestJS 11 + PG 16,
one 4 GB OVH VPS, Windows 11 dev box, OMP primary harness / Claude Code secondary).

All star counts, `pushed_at` values and commit dates in this file were read from
`api.github.com` (authenticated `gh api`) between 2026-09-12T03:45Z and 04:20Z. Where a figure
came from a rendered doc page or a README rather than the API, it says so. Nothing in this file
is sourced from a blog post, listicle or "awesome" list.

MCP servers are out of scope here (separate file).

---

## 0. Method and the one thing that invalidates most advice

Two facts govern every verdict below, and they are the reason a popular tool can still be a bad
fit for this box:

1. **OMP does not implement Claude Code hooks.** OMP's hook subsystem is TypeScript modules that
   default-export a factory receiving a `HookAPI` and register handlers with `pi.on(...)`. Its
   event names are `session_start`, `session_shutdown`, `context`, `tool_call`, `tool_result`,
   `turn_start`, `turn_end`, `session_before_compact`, `agent_end`, … — **not** `PreToolUse`,
   `PostToolUse`, `Stop`, `SessionStart`. `--hook` is an alias for `--extension`; discovered
   paths are `.omp/hooks/pre/*.ts`. A plugin's `hooks/hooks.json` is inert under OMP.
   (`https://github.com/can1357/oh-my-pi/blob/main/docs/hooks.md`)
2. **OMP *does* read Claude Code skills.** `loadSkills()` registers providers in priority order:
   `native` (`.omp`, 100) → `omp-plugins` (90) → `claude` (`.claude/skills`, 80) → `claude-plugins`
   / `agents` / `codex` (70) → `opencode` (55) → `github` (30) → `omp-managed` (5). Dedup key is
   the skill name, highest-priority provider wins.
   (`https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md`)

**Consequence:** for this box, a *skills-only* Claude Code plugin is a genuine cross-harness win
(OMP picks it up through the `claude-plugins` provider). A plugin whose value is in its hooks
(`security-guidance`, `ralph-loop`, `superpowers`' bootstrap, `hookify`'s output) works in Claude
Code only and silently does nothing in OMP.

Second portability trap: **OMP supports a much smaller SKILL.md frontmatter surface.** OMP reads
`name`, `description`, `globs`, `alwaysApply`, `hide`, `disableModelInvocation` (normalising
`disable-model-invocation`); everything else is "preserved as unknown metadata", i.e. ignored.
So `allowed-tools`, `context: fork`, `agent`, `background`, `hooks`, `paths`, `model`, `effort`,
`arguments`, `argument-hint` — the entire Claude Code extension set — are **no-ops under OMP**.
Any skill whose control flow depends on `context: fork` or `allowed-tools` degrades to plain prose
here. Also: OMP provider discovery is **non-recursive one level under `skills/`**, so
`skills/engineering/tdd/SKILL.md` (mattpocock's layout) is *not* discovered by a provider — it needs
`skills.customDirectories` pointed at `skills/engineering`.

---

## 1. First-party marketplace: `anthropics/claude-plugins-official`

**Provenance:** owner `anthropics`, Apache-2.0, 36 153★, 4 058 forks, created 2025-11-20,
`pushed_at` 2026-09-11T16:08:29Z, not archived. `.claude-plugin/marketplace.json` lists **295
plugins total**, of which **39 are first-party** (`source: "./plugins/<name>"`); the remaining
~256 are third-party entries pulled by `git-subdir` reference plus 14 vendored `external_plugins/`
(`asana`, `context7`, `discord`, `fakechat`, `firebase`, `github`, `gitlab`, `imessage`,
`laravel-boost`, `linear`, `playwright`, `serena`, `telegram`, `terraform`).
There are no GitHub releases; versions live in each `plugin.json`.

### 1.1 Every first-party plugin, last touched, and change volume since 2026-04-15

`last commit` = `commits?path=plugins/<name>&per_page=1`; `Δ` = commit count with
`since=2026-04-15T00:00:00Z` (the day this box installed its plugins).

| Plugin | Last commit | Δ since 2026-04-15 | Verdict for this box |
|---|---|---|---|
| `security-guidance` | 2026-09-09 | **35** | **Do not install** — hooks-only value, needs Python venv (see §2.1) |
| `code-modernization` | 2026-07-09 | **20** | Do not install — COBOL/monolith uplift; no legacy tier here |
| `claude-security` | 2026-09-01 | **7** | **Consider** — in-session scanner, no daemon (see §2.2) |
| `mcp-tunnels` | 2026-05-21 | 3 | Do not install — exposes local MCP over a tunnel; wrong for an E2EE repo |
| `receipts` | 2026-07-21 | 3 | Do not install — manager-justification report; solo maintainer |
| `project-artifact` | 2026-08-13 | 3 | Do not install — publishes a status page to claude.ai (egress) |
| `frontend-design` | 2026-09-01 | 2 | Do not install — HTML/CSS-shaped; superseded locally (see §3.2) |
| `hookify` | 2026-05-20 | 2 | Do not install — authors Claude-Code-only `hooks.json` |
| `mcp-server-dev` | 2026-04-28 | 2 | Do not install — not writing MCP servers |
| `plugin-dev` | 2026-08-06 | 2 | Do not install — not authoring CC plugins |
| `cwc-makers` | 2026-05-06 | 2 | Do not install |
| `claude-code-setup` | 2026-05-28 | 1 | Do not install — one-shot recommender |
| `pr-review-toolkit` | 2026-04-28 | 1 | Do not install — `code-review` + `gh` covers it |
| `skill-creator` | 2026-04-23 | 1 | **Install (worth it)** — eval harness, no runtime footprint (§2.3) |
| `code-review` | 2026-02-20 | 0 | **Already have** — installed copy is current |
| `claude-md-management` | 2026-02-20 | 0 | **Already have** — installed copy is current (v1.0.0) |
| `session-report` | 2026-04-10 | 0 | Do not install — reads `~/.claude/projects`; OMP writes `~/.omp` |
| `example-plugin` | 2026-03-17 | 0 | n/a |
| `explanatory-output-style` | 2026-03-28 | 0 | Do not install |
| `learning-output-style` | 2026-03-28 | 0 | Do not install |
| `ralph-loop` | 2026-03-28 | 0 | Do not install — Stop-hook loop; hook is inert in OMP |
| `math-olympiad` | 2026-03-30 | 0 | n/a |
| `ruby-lsp` | 2026-03-13 | 0 | n/a |
| `agent-sdk-dev`, `claude-md-management`, `code-simplifier`, `commit-commands`, `feature-dev`, `playground` | 2026-02-20 | 0 | Do not install — dormant since Feb |
| LSP plugins: `clangd`, `csharp`, `gopls`, `jdtls`, `kotlin`, `lua`, `php`, `pyright`, `rust-analyzer`, `swift`, `typescript` | 2026-02-20 / 2026-03-13 | 0 | Do not install — **there is no `dart-lsp` / `analysis_server` plugin**, and OMP has its own `lsp-config`; the TS one is redundant with OMP's LSP wiring |

**Answer to (1): four first-party plugins have material change since 2026-04.**
`security-guidance` (35 commits, 2.0.5 → 2.0.8), `code-modernization` (20), `claude-security`
(v0.10.1-rc7 → v0.11.0, 7), and a long tail of ≤3-commit touches. **Neither plugin this box
actually installed on 2026-04-15 has changed at all**: `code-review` and `claude-md-management`
are both last-touched 2026-02-20, zero commits since April. The `"version": "unknown"` recorded in
`installed_plugins.json` for `code-review` is because that plugin's `plugin.json` carries no
`version` field — not a stale install. **No action needed on the installed pair.**

### 1.2 On-box install state (read from disk, not inferred)

`C:\Users\Lentach\.claude\plugins\installed_plugins.json`:

| Entry | Scope | Version | Installed / lastUpdated |
|---|---|---|---|
| `code-review@claude-plugins-official` | user | `unknown` | 2026-04-15T23:23:47Z |
| `claude-md-management@claude-plugins-official` | user | `1.0.0` | 2026-04-16T02:44:57Z |

Also on disk but **not** in `installed_plugins.json` — orphaned cache with `.orphaned_at` markers:
`context7`, `playwright`, `code-simplifier/1.0.0`, `frontend-design`, `skill-creator`,
`ralph-loop/1.0.0`. Plus empty `plugins/data/` dirs for `datadog-inline`, `ralph-loop-inline`,
`superpowers-inline`, `context7-inline`, `playwright-inline`. **Verdict: dead weight.** These are
leftovers from earlier experiments; the marketplace mirror under
`.claude/plugins/marketplaces/claude-plugins-official/` is a full checkout that costs disk only.
Safe to delete the orphaned cache dirs; nothing references them.

---

## 2. The three first-party plugins that are actually decidable

### 2.1 `security-guidance` — **do not install**

- **What:** pattern-based warnings on edits, an LLM diff review on `Stop`, and an agentic commit
  reviewer for injection/XSS/SSRF/hardcoded secrets and "25+ other vulnerability classes".
- **Provenance:** author `David Dworken <dworken@anthropic.com>`, in-repo (Apache-2.0 umbrella),
  `plugin.json` **v2.0.8**; last commit 2026-09-09 ("resolve repository from command and edited
  paths", "Harden git invocation", "Adjust SubagentStop handling"). 35 commits since April.
- **Install surface:** Claude Code plugin, value entirely in `hooks/hooks.json` +
  `hooks/*.py` (`sg-python.sh`, `ensure_agent_sdk.py`, `llm.py`, `review_api.py`).
- **Egress:** sends diffs to the Anthropic API for the LLM review; `ensure_agent_sdk.py` +
  the 2026-06 commits ("pip `--target` fallback when venv can't bootstrap pip", "handle
  signal-killed venv builds") mean it **builds a Python venv and pip-installs the Agent SDK** on
  first run, i.e. PyPI egress and a Python 3.10+ requirement it probes for.
- **Fit verdict: NO.** Three independent disqualifiers. (a) It is a hooks plugin, so under OMP —
  the primary harness — it does nothing at all. (b) Its entry point is `sg-python.sh` invoked via
  bash; on Windows 11 this needs Git Bash and the known `hub start` `.bat` limitation is the same
  class of problem. (c) It ships an unpinned pip bootstrap into an E2EE repo's toolchain. The
  already-installed `gitleaks` covers the hardcoded-secret class deterministically and offline.

### 2.2 `claude-security` — **consider, with eyes open**

- **What:** deep vulnerability scan of your own code, run entirely inside the Claude Code session
  at a chosen effort tier; every finding is challenged before reporting; surviving findings become
  patches you apply manually.
- **Provenance:** author `Anthropic <support@anthropic.com>`, `plugin.json` **v0.11.0**,
  license `SEE LICENSE IN LICENSE` (i.e. **not** plain Apache-2.0 — a bespoke licence file).
  Release cadence visible in commits: v0.10.1-rc7 (2026-08-17) → v0.10.2 (08-21) → v0.10.2.3
  (08-24) → v0.11.0 (2026-09-01).
- **Install surface:** Claude Code plugin, skills + agents (no daemon, no venv, no MCP server).
- **Egress:** normal session model traffic only — the scan runs as subagents in-session. No
  third-party endpoint.
- **Fit verdict: MAYBE — one-shot, Claude-Code-only.** It costs nothing at rest and the "challenge
  every finding" design is the right shape for a solo maintainer who cannot triage a noisy scanner.
  But: pre-1.0 with a `0.10.2.3`-style version scheme, a non-standard licence, and it only runs
  under Claude Code (the secondary harness). This repo already has a `security-reviewer` agent and
  `osv-scanner`/`trivy`/`gitleaks`. **Use it as an occasional second opinion via `claude`, do not
  make it part of the loop.** Note the July audit's reasoning is unchanged: nothing here replaces
  the three installed scanners.

### 2.3 `skill-creator` — **install**

- **What:** create/improve skills and, more importantly, **measure** them: `evals/evals.json` test
  cases, one subagent per case for clean context, `grading.json`, `benchmark.json` aggregating
  pass-rate/time/tokens with-skill vs without-skill, blind A/B between two skill versions, and
  description tuning that generates should-trigger / should-not-trigger prompts and reports hit rate.
- **Provenance:** author `Anthropic`, in-repo, last commit 2026-04-23 ("sync from
  `anthropics/skills` (drop `ANTHROPIC_API_KEY` requirement)"). The same skill also ships in
  `anthropics/skills` at `skills/skill-creator/` with its own `LICENSE.txt`. Scripts are Python
  (`run_eval.py`, `improve_description.py`, `aggregate_benchmark.py`, `package_skill.py`).
- **Install surface:** `/plugin install skill-creator@claude-plugins-official`. Already sitting
  orphaned in this box's plugin cache, so the bytes are local.
- **Egress:** runs subagents against the session model; no third-party endpoint. `package_skill.py`
  is local packaging.
- **Fit verdict: YES, for one specific job.** This repo authors its own skills
  (`umbra-session-end`, `flutter-frontend-design`) and has **no way to test whether a description
  actually triggers**. The description-tuning + benchmark loop is the only primary-source tool that
  answers "is this skill earning its 1 536 characters of listing budget?" Claude-Code-only, but
  that's fine: authoring is a one-off activity, and the SKILL.md it produces is portable to OMP as
  long as you stick to the six spec fields (§4.3).

---

## 3. Flutter / Dart skills

**Answer to (2): yes — one collection with real provenance, and it is not a UI collection.**

### 3.1 `kevmoo/dash_skills` — **install (via `skills.customDirectories` or vendored)**

- **What:** "Agent Skills for Dart and Flutter ecosystem" — 11 skills: `dart-best-practices`,
  `dart-doc-validation`, `dart-long-lines`, `dart-matcher-best-practices`, `dart-modern-features`,
  `dart-multiline-strings`, `dart-package-maintenance`, `dart-test-coverage`,
  `dart-test-fundamentals`, `dash-discover`, `profile-dart-code`.
- **Provenance:** owner **Kevin Moore** (`kevmoo`), GitHub profile company `@dart-lang @flutter
  @google` — i.e. a Dart/Flutter team member, which is as close to first-party as Dart skills get.
  **Apache-2.0**, 144★, created 2026-01-20, `pushed_at` **2026-09-12T03:41:45Z** (today).
  **No GitHub releases** — `main` is the distribution channel. Repo carries `.claude-plugin/`,
  `plugins/dash-skills`, `evals/`, `GEMINI.md`, topic `agent-skills`.
- **Install surface:** Claude Code plugin (`plugins/dash-skills`) **or** point OMP
  `skills.customDirectories` at the repo's `skills/` — the layout is one level under `skills/`, so
  OMP's non-recursive provider scan works directly.
- **Egress:** none. Prose skills; `profile-dart-code` drives local DevTools/VM-service.
- **Fit verdict: YES — best Dart/Flutter skill fit found, but scope it.** The star count is low
  (144) because the audience is small, not because it's unmaintained — it was pushed today and is
  owned by a Dart team member, which beats a 90 k★ generic collection on provenance. For this repo
  the earners are `dart-test-fundamentals`, `dart-matcher-best-practices`, `dart-test-coverage`
  (this repo's tests are load-bearing) and `profile-dart-code` (Flutter web perf on a 4 GB VPS
  budget). `dart-package-maintenance` and `dart-doc-validation` are for pub package authors — skip;
  each unused skill costs listing budget every turn (§4.1). **Verify before adopting:** it has no
  release tags, so pin a commit SHA if you vendor it.
- **Caveat:** it overlaps the already-mounted **Dart MCP** (on probation since July). `dash_skills`
  is prose guidance; Dart MCP is tool access. They are not substitutes and both were pushed this
  week. No change to Dart MCP's probation status from this survey.

### 3.2 The other Flutter collections — **do not install**

Ranked by stars, all read from the API:

| Repo | ★ | License | `pushed_at` | Verdict |
|---|---|---|---|---|
| `MADTeacher/mad-agents-skills` | 108 | MIT | **2026-05-01** | No — 4 months stale, no named provenance |
| `cometchat/cometchat-skills` | 104 | MIT | 2026-09-11 | No — vendor SDK integration skills (CometChat is a *competing* messaging backend) |
| `cleydson/flutter-claude-code` | 53 | **none** | 2026-03-04 | No — unlicensed, 6 months stale |
| `fluttersdk/wind` | 33 | MIT | 2026-09-10 | No — Tailwind-for-Flutter DSL; a new styling convention beside the existing `ThemeExtension` system is a regression here |
| `RandalSchwartz/dart-sdk-skills` | 29 | MIT | 2026-09-01 | Marginal — SDK versioning / widget migrations / minSdk lookups. Real named author, active. Useful only at Flutter-upgrade time; not worth standing listing budget |
| `anasfik/FlutterGuard` | 25 | **none** | 2026-08-24 | No — unlicensed. Ironic for an APK/AAB *security* skill; would be interesting for the Android tier if it had a licence |
| `sgaabdu4/building-flutter-apps` | 22 | MIT | 2026-09-09 | No — prescribes Riverpod 3.x + Freezed 3.x clean architecture; this repo has its own state layer |
| `lh17708357536-gif/flutter-cn-overseas-app-skills` | 20 | MIT | 2026-07-13 | No — Flutter+NestJS, so nominally on-stack, but CN-market flavors/third-party login/CI; unknown author |
| `conalyz/conalyz_cli` | 13 | MIT | 2026-07-02 | No — WCAG analyser CLI; the local `flutter-frontend-design` skill already mandates ≥4.5:1 verification |
| `ImL1s/flutter-claude-skills` | 10 | MIT | 2026-09-07 | No — "66 curated skills" at 10★ is a quantity signal, not a quality one |
| `thiennc-tesoglobal/flutter-skills` | 7 | BSD-3 | 2026-09-11 | No |
| `aiopshwang/ship-mobile-app` | 8 | MIT | 2026-08-27 | No |

### 3.3 Provenance of this box's `flutter-frontend-design` — **locally authored; no upstream**

I could not find an upstream, and the evidence is that there isn't one:

- `search/repositories?q=flutter-frontend-design` returns only unrelated Flutter *apps*
  (`israelglory/Job-UI` etc.), no skill repo.
- `search/code?q=flutter-frontend-design+in:path` returns 10 hits, all in unrelated scaffolding
  dumps: `Disesfgewu/agent-client-template`, `charansaikondilla/ceomans`, `bakka22/dawaai`,
  `haysan10/natasaku/_archive/...`, plus a superpowers *spec* file in `ajones8131/run-planner`.
- I fetched the closest-named one (`charansaikondilla/ceomans`,
  `.claude/skills/flutter-frontend-design/SKILL.md`, 9 709 bytes, `license: MIT`) and diffed by
  inspection: **different text entirely**. Its description is "Create distinctive, production-grade
  Flutter mobile & web UI…"; ours is "Build distinctive, production-grade Flutter UI … avoids
  generic 'AI slop' … Prefer this over the generic web frontend-design skill anytime the target is
  Flutter". No shared headings.
- It is also **not** a copy of Anthropic's `frontend-design`
  (`anthropics/skills/skills/frontend-design/SKILL.md`, 9 363 bytes, `license: Complete terms in
  LICENSE.txt`). That skill opens "Approach this as the design lead at a design studio…" and is
  medium-agnostic/CSS-shaped; it contains nothing about `ThemeExtension`, `flutter_animate`,
  `MediaQuery.disableAnimationsOf`, or iOS-web keyboard insets.

**Verdict: already have, keep, no upstream to track.** The local skill is a hand-written
Flutter-native counterpart to the Anthropic `frontend-design` concept, and it encodes
project-specific knowledge (`.disableAnimationsOf` reduce-motion gate, "do not animate
keyboard-adjacent chrome", capped stagger, `pubspec.yaml` dependency discipline) that no surveyed
third-party skill contains. The *name* collision with several unrelated repos is coincidence —
it's an obvious name. Two notes:
- Its `description` is ~740 characters, well inside the 1 536-char cap (§4.1) — but it is one of
  the longest descriptions on the box and it uses the whole budget on trigger phrases. That is the
  correct trade for a skill you want auto-invoked.
- It sits at **user level** (`~/.claude/skills/`), so it is invisible to cloud/Cowork sessions and
  is not versioned with the repo. If it is load-bearing for Umbra work, it belongs in
  `.omp/skills/` or `.claude/skills/` **in the repo**. Flagging, not changing.

---

## 4. Current spec: skills, hooks, token cost

### 4.1 Token cost model — answer to (4)

From `https://code.claude.com/docs/en/skills` (read 2026-09-12; canonical URL now
`code.claude.com/docs/en/skills`, the `docs.claude.com/en/docs/claude-code/skills` URL redirects
there):

**Descriptions — the standing cost.**
- "Every skill in the skill listing adds to your context **on every turn**, whether or not Claude
  ever uses it."
- The combined `description` + `when_to_use` text is **truncated at 1 536 characters** in the
  listing. Put the key use case first.
- The whole listing has a **character budget of 1 % of the model's context window**, settable via
  `skillListingBudgetFraction` or a fixed `SLASH_COMMAND_TOOL_CHAR_BUDGET`.
- On overflow, Claude Code **keeps every skill name but drops descriptions, starting with the
  skills you invoke least** — i.e. a rarely-used skill degrades gracefully, but a *new* skill can
  silently lose the keywords that would trigger it. A warning goes to `--debug`.
- `skillOverrides: {"x": "name-only"}` lists a skill without its description to free budget;
  `"off"` hides it entirely. Plugin skills are exempt from `skillOverrides` — manage via `/plugin`.
- `/skill-doctor` (v2.1.252+) reports per-skill context cost and invocation count and names
  never-invoked skills. `/context`'s Skills row reports the post-budget size.

**Bodies — when they load and what they then cost.**
- "A skill's body loads only when it's used, so long reference material costs almost nothing until
  you need it." In a regular session only descriptions are in context; full content loads on invoke.
- **But it does not unload.** "When you or Claude invoke a skill, the rendered `SKILL.md` content
  enters the conversation as a single message and **stays there across later turns**… Claude Code
  does not re-read the skill file on later turns." Therefore: "Keep the body itself concise… every
  line is a recurring token cost. State what to do rather than narrating how or why."
- **Compaction budget:** auto-compaction re-attaches the most recent invocation of each skill after
  the summary, **keeping the first 5 000 tokens of each**, with a **combined 25 000-token budget**
  filled from the most recently invoked skill backwards. Older skills can be dropped entirely.
- Corollary the docs state explicitly: if a skill seems to stop working, the content is usually
  still present and the model is choosing otherwise — "use hooks to enforce behavior
  deterministically."
- Progressive disclosure mechanism: `${CLAUDE_SKILL_DIR}` + supporting files, so the body stays
  thin and references load on demand. `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/x.sh *)`
  lets a bundled script run without a prompt.

**Applied to this repo (counts measured on disk, 2026-09-12):** `umbra-session-end` is ~3.2 KB of
body — comfortably inside the 5 000-token compaction slice, so it survives a compact intact.
`flutter-frontend-design` is ~9 KB; at roughly 2.5 KB/1 000 tokens that is ~3.6 k tokens, also
inside the slice. Neither needs splitting. The real exposure is the inventory:

| Root | Entries | Note |
|---|---|---|
| `~/.agents/skills/` | **39** real dirs | full mattpocock set, including 7 skills upstream has since deleted or renamed |
| `~/.claude/skills/` | **12** entries | 10 are **symlinks** into `~/.agents/skills/` (`readlink` confirmed); only `flutter-frontend-design` and `planning-with-files` are real dirs |
| `.omp/skills/` (repo) | **1** | `umbra-session-end` |

**The symlink layout is correct and should be left alone.** Claude Code's docs state a skill entry
"can be a symlink to a directory elsewhere on disk. Claude Code reads `SKILL.md` from the target
and loads the skill once even if several locations point at the same target." OMP's `skills.ts`
independently "de-duplicates identical files by `realpath` (symlink-safe)". So the `agents`
(priority 70) and `claude` (priority 80) providers resolve to the same inode and cost the listing
once, not twice.

The real exposure is the other direction: the harness advertises **18** skills while **41**
distinct `SKILL.md` files exist on disk, so ~23 are dormant bytes — and, more importantly, four of
the advertised 18 are skills the upstream author has deleted (§6.3). `/skill-doctor` is the
primary-source way to find which of the 18 have never fired. **Action: run `/skill-doctor` in a
`claude -p` run and set never-invoked entries to `"name-only"` in `skillOverrides`.** No install
required.

### 4.2 Hooks — answer to (3), documented events

From `https://code.claude.com/docs/en/hooks` (read 2026-09-12). Cadences: per-session
(`SessionStart`, `SessionEnd`), per-turn (`UserPromptSubmit`, `Stop`, `StopFailure`), per-tool-call
(`PreToolUse`, `PostToolUse`, except `EndConversation` which skips both). The three you asked about:

**`PreToolUse`** — fires after Claude builds tool parameters, before the call. Matches any tool but
`EndConversation`, including MCP tool names. Input adds `tool_name`, `tool_input`, `tool_use_id`.
Decision lives in `hookSpecificOutput`: `permissionDecision` ∈ `allow` | `deny` | `ask` | `defer`
plus `permissionDecisionReason`; `updatedInput` replaces the *entire* input object before execution
(permission rules and Bash auto-background eligibility are re-evaluated against the hook's version);
`additionalContext` injects a system reminder. Multi-hook precedence: `deny` > `defer` > `ask` >
`allow`. Exit 2 blocks regardless of JSON. `defer` is honoured only under `-p`.

**`Stop`** — fires when the main agent finishes responding; does **not** fire on user interrupt
(API errors route to `StopFailure` instead). Input adds `stop_hook_active`, `last_assistant_message`,
`background_tasks`, `session_crons`. Decision is **top-level** `{"decision":"block","reason":…}`
(distinct from `PreToolUse`); `hookSpecificOutput.additionalContext` is the softer channel —
conversation continues, transcript labels it `Stop hook feedback`, no error notification. Loop
guards: `stop_hook_active` plus a hard cap of **8 consecutive blocks**. `SubagentStop` uses the same
format and additionally carries `agent_id`, `agent_type`, `agent_transcript_path`.

**`SessionStart`** — fires on new session or resume; `source` ∈ `startup` | `resume` | `fork` |
`clear` | `compact`. **No blocking.** Context-only, but with four extras beyond
`additionalContext`: `initialUserMessage` (creates the first turn, `-p` only), `sessionTitle`
(ignored on `clear`/`compact`), `watchPaths` (arms `FileChanged`), and **`reloadSkills: true`**
(re-scans skill/command dirs after SessionStart hooks so skills the hook installed are live in the
same session). `CLAUDE_ENV_FILE` persists env vars into later Bash calls.

Universal output fields: `continue` (false stops everything, beats event-specific decisions),
`stopReason`, `systemMessage`, `terminalSequence` (OSC 0/1/2/9/99/777 + BEL — the supported way to
notify, since hooks have no `/dev/tty`; explicitly called out as the Windows-safe path).
All hook output strings including `additionalContext` are **capped at 10 000 characters**; overflow
is spilled to a file and replaced with a preview + path. Handler types are `command`, `http`,
`mcp_tool`, `prompt`, and `agent`. Matchers: `*`/empty = all; alphanumeric+`_-`,`|` = exact
string(s); anything else = unanchored JS regex. There is also an `if` field (e.g.
`"if": "Bash(rm *)"`) that gates the handler *before* the process spawns.

**Does OMP honour Claude Code hooks? No.** See §0.1. OMP's `docs/hooks.md` documents a completely
separate TypeScript event bus; `hooks.json` is never read. Practical mapping if you ever want the
equivalent under OMP:

| Claude Code | Nearest OMP event |
|---|---|
| `PreToolUse` (block/rewrite input) | `tool_call` → `{ block, reason, input }` |
| `PostToolUse` (rewrite output) | `tool_result` → `{ content, details }` |
| `SessionStart` (`additionalContext`) | `session_start` + `context` → `{ messages }` |
| `Stop` (block completion) | no equivalent; closest is `turn_end` / `agent_end` (observational) |
| `PreCompact` / `PostCompact` | `session_before_compact` / `session.compacting` / `session_compact` |
| `SessionEnd` | `session_shutdown` |

Note the **gap that matters for this repo**: OMP has **no `Stop`-equivalent that can block turn
completion.** `umbra-session-end`'s enforcement therefore cannot be a hook under OMP — and it
isn't: it is enforced by `.githooks/pre-commit` → `scripts/verify-context-budget.mjs`, which is
harness-independent and strictly better. See §5.

Also relevant: `security-guidance`'s newest commit adjusts **`SubagentStop`** handling, and
`superpowers` ships exactly one hook, `SessionStart` with matcher `startup|clear|compact` calling
`run-hook.cmd session-start` with `"shell": "bash"`. Both are Claude-Code-only mechanisms.

### 4.3 Frontmatter spec, and the portability rule

`anthropics/skills/spec/agent-skills-spec.md` is now a **one-line stub** pointing at
`https://agentskills.io/specification` — the spec has moved out of the repo. The authoritative
field list readable from a primary source is Claude Code's own table:

`name`, `description`, `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`,
`user-invocable`, `allowed-tools`, `disallowed-tools`, `model`, `effort`, `context`, `agent`,
`background`, `hooks`, `paths`, `shell`, `metadata`, `license`, `compatibility`.
All optional; only `description` recommended (falls back to the first non-empty body line).
Frontmatter is parsed **only if the opening `---` is line 1**; malformed YAML means the body loads
with empty metadata, so `/skill-name` still works but auto-matching dies (visible under `--debug`).
Booleans accept `yes/no/on/off/1/0` since v2.1.218.

**The portability rule, stated by the docs:** outside Claude Code only **six** fields are legal —
`name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`. claude.ai uploads,
the Skills API, and `package_skill.py` reject anything else with
`Unexpected key(s) in SKILL.md frontmatter: … Allowed properties are: allowed-tools, compatibility,
description, license, metadata, name`. Cross-referenced with §0.2 (OMP reads only
`name`/`description`/`globs`/`alwaysApply`/`hide`/`disableModelInvocation`), the **safe intersection
for a skill that must work in both OMP and Claude Code is `name` + `description`** — plus
`disable-model-invocation` if you want manual-only, since OMP normalises exactly that kebab-case
key. Both of this repo's own skills already conform. `claude plugin validate .claude/skills`
(v2.1.233+) finds files whose frontmatter doesn't parse.

Two Claude Code body features that are **dead under OMP**: dynamic context injection
(`` !`git diff HEAD` ``, ` ```! ` blocks) and `${CLAUDE_*}` substitutions. OMP's skill invocation
strips frontmatter, wraps the body, and appends `[Skill directory: <baseDir>]` — no command
execution, no placeholder expansion. A skill whose first section is `!`command`` will show Claude
the literal backtick line under OMP.

---

## 5. Session-end / handoff — answer to (5)

**No mature skill does what `umbra-session-end` does. The closest primary-source options are both
strictly weaker, and OMP already ships the generic half of the job as a built-in.**

What `umbra-session-end` actually does (read from `.omp/skills/umbra-session-end/SKILL.md`): three
files with three lifetimes — a dated summary under `.cursor/session-summaries/` with four
hook-checked `##` headings and an 8 000-byte hard cap, one-line trap appends into
`docs/agents/traps.md` under fixed groups, and a 5-entry FIFO rotation of `LATEST.md` with a
900-char-per-entry cap — and it is **enforced by `.githooks/pre-commit` running
`scripts/verify-context-budget.mjs`, which refuses the commit** when a cap breaks.

Candidates:

### 5.1 `mattpocock/skills` → `productivity/handoff` — **do not install**

- **What:** 894 bytes total. "Compact the current conversation into a handoff document for another
  agent to pick up. Save to the temporary directory of the user's OS — **not the current
  workspace**." Frontmatter: `disable-model-invocation: true`, `argument-hint: "What will the next
  session be used for?"`.
- **Provenance:** MIT, part of plugin `mattpocock-skills` v1.2.3 (release `v1.2.3`,
  2026-08-06T14:05:28Z); repo 259 871★, `pushed_at` 2026-09-04.
- **Fit verdict: NO, and the upstream author agrees.** Three mismatches. (a) It writes to the OS
  temp dir by design; `umbra-session-end` writes versioned repo artifacts — the opposite contract.
  (b) No caps, no enforcement, no rotation, no trap ledger. (c) The upstream CHANGELOG for
  `/ask-matt` (PR #763) explicitly narrows it: "**`/handoff` was oversold.** It read as the general
  bridge between context windows. It's narrow: you need it only when something has to *travel* — a
  new harness, a new directory, a colleague, or a side task forked mid-phase. What it buys is
  portability." Umbra's session-end is a durable-record discipline, not a portability escape hatch.
  There is also an `in-progress/claude-handoff` beta variant — beta channel, not a candidate.

### 5.2 OMP built-in `/handoff` — **already have; know its limits**

`https://github.com/can1357/oh-my-pi/blob/main/docs/handoff-generation-pipeline.md` documents a
first-class `/handoff` slash command: `AgentSession.handoff()` → `SessionMaintenance.handoff()` →
`SessionHandoff.generateDocument(...)`, with the generated document **committed as a compaction
entry** in the session tree, plus `[focus instructions]` as an inline hint. That is the
conversation-compaction half, in-session, zero install.
**Verdict: already have.** It does not write dated repo files, does not touch `traps.md`, and has
no cap enforcement — so it complements `umbra-session-end` rather than replacing it. Use `/handoff`
mid-session when context must travel; use `umbra-session-end` at the commit boundary.

### 5.3 `session-report` / `receipts` — **do not install**

Both read `~/.claude/projects` transcripts (`session-report` renders an HTML report of
tokens/cache/subagents/skills; `receipts` produces a usage-justification writeup and, per its own
description, sends "only counts and project names" out to write it up). **Verdict: NO.** Under OMP
the transcripts live in `~/.omp/agent/sessions/`, so both read an almost-empty directory on this
box. `receipts` additionally has egress and exists to justify usage to a manager — irrelevant to a
solo maintainer.

**Conclusion: keep `umbra-session-end` as-is.** Its differentiator is the pre-commit gate, and the
docs (§4.1) independently validate that choice: *"use hooks to enforce behavior deterministically"*
rather than trusting a skill body to keep influencing the model after compaction. A git hook is a
stronger version of that advice than any Claude Code hook, because it survives the harness switch.

---

## 6. Third-party skill collections

### 6.1 `anthropics/skills` — **do not install wholesale; cherry-pick `skill-creator`**

- **What:** 19 skills — `academy-guide`, `algorithmic-art`, `brand-guidelines`, `canvas-design`,
  `claude-api`, `discernment-nudge`, `doc-coauthoring`, `docx`, `frontend-design`,
  `internal-comms`, `mcp-builder`, `pdf`, `pptx`, `skill-creator`, `slack-gif-creator`,
  `theme-factory`, `web-artifacts-builder`, `webapp-testing`, `xlsx`.
- **Provenance:** owner `anthropics`, **`license: null` at repo level** (per-skill `LICENSE.txt`
  files instead, plus a 46 KB `THIRD_PARTY_NOTICES.md`), 175 872★, 20 810 forks, created
  2025-09-22, `pushed_at` 2026-09-10T19:44:11Z, topic `agent-skills`. Also ships `.claude-plugin/`
  and a `template/`.
- **Install surface:** Claude Code plugin / copy a skill dir.
- **Egress:** none inherent (document skills are local converters).
- **Fit verdict: mostly NO.** The centre of gravity is document generation (`docx`/`pdf`/`pptx`/
  `xlsx`) and brand/marketing/canvas work — none of which this repo does. `webapp-testing` is
  Playwright-shaped and OMP already has a first-class `browser` object in Eval, which is the
  verification surface this repo uses. `frontend-design` is superseded by the local Flutter skill
  (§3.3). `mcp-builder` is irrelevant (not authoring MCP servers). **Cherry-pick `skill-creator`
  only** (§2.3). Note the repo-level `license: null` — if you vendor anything, copy its
  `LICENSE.txt` with it.

### 6.2 `obra/superpowers` — **do not install as a plugin; consider as a skills directory**

- **What:** "An agentic skills framework & software development methodology". 14 skills:
  `brainstorming`, `dispatching-parallel-agents`, `executing-plans`,
  `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`,
  `subagent-driven-development`, `systematic-debugging`, `test-driven-development`,
  `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`,
  `writing-skills`.
- **Provenance:** Jesse Vincent (`jesse@fsck.com`), **MIT**, 285 421★ (highest in this survey),
  25 522 forks, created 2025-10-09, `pushed_at` 2026-09-12T00:16:38Z, plugin **v6.3.0**, release
  `v6.3.0` @ 2026-08-12T16:58:30Z. Listed in the official marketplace
  (`/plugin install superpowers@claude-plugins-official`). Ships per-harness dirs for Claude,
  Codex, Cursor, Devin, Hermes, Kimi, OpenCode, Gemini, **and `.pi/`**.
- **Install surface (relevant ones):** official Claude marketplace; or `pi install
  git:github.com/obra/superpowers`; or `pi -e /path/to/superpowers` for dev.
- **Egress:** none for the skills. One hook: `hooks/hooks.json` = a single `SessionStart` entry
  (matcher `startup|clear|compact`) running `run-hook.cmd session-start` under bash.
- **Fit verdict: NO as a plugin, MAYBE as a skills dir — and here is the specific reason.** I read
  `.pi/extensions/superpowers.ts`: it type-imports `ExtensionAPI` from
  **`@earendil-works/pi-coding-agent`** — pi-mono's package, not OMP's `@oh-my-pi/pi-coding-agent`
  — and it registers `pi.on("resources_discover")` to hand back `skillPaths`. **`resources_discover`
  is not in OMP's documented event surface**, so the skill-path registration is the one handler
  most likely to no-op under OMP, while its `session_start`/`session_compact`/`agent_end`/`context`
  handlers (which inject the `using-superpowers` bootstrap) do exist in OMP's bus. That's a
  half-working extension: bootstrap injected, skills not registered. Meanwhile the Claude Code
  `SessionStart` hook that does the same job under Claude Code is inert in OMP. **If you want these
  skills under OMP, skip both installers and point `skills.customDirectories` at the checkout's
  `skills/` directory** — that layout is one level deep, so OMP's non-recursive scan works.
  Separately, the content overlaps heavily with what this box already has: `test-driven-development`
  ≈ local `tdd`, `systematic-debugging` ≈ `diagnosing-bugs`, `requesting-code-review` ≈
  `code-review`, `writing-plans` ≈ `planning-with-files`, `dispatching-parallel-agents` ≈ OMP's
  native `task`/`workpool`. Adding 14 more descriptions to a listing that already holds 18 skills
  is a direct hit on the 1 %-of-context budget (§4.1) for near-duplicate guidance. **Net: no.**

### 6.3 `mattpocock/skills` — the delta since this repo's cull

- **Provenance:** Matt Pocock, **MIT**, 259 871★, 21 916 forks, created 2026-02-03, `pushed_at`
  2026-09-04T08:45:43Z. Plugin `mattpocock-skills` **v1.2.3**, release `v1.2.3` @
  2026-08-06T14:05:28Z (prior: v1.2.2 @ 2026-08-05, v1.2.0 @ 2026-08-05). Layout is
  `skills/{engineering,productivity,misc,in-progress,deprecated}/<name>/SKILL.md` — **two levels
  deep, so OMP provider discovery will not find it** without `customDirectories` per bucket.
  Distribution: Claude Code plugin (25 skills listed in `.claude-plugin/plugin.json`) or
  skills.sh per-skill.

**Answer to "what changed", verified against `~/.agents/skills/` (39 dirs, all with a `SKILL.md`):
seven of the on-disk skills no longer exist upstream at all, and the CHANGELOG names exactly where
each went** (PR #752, "Remove six skills from the repo"; `writing-great-skills` was renamed
separately, per PR #766):

| Local skill | Upstream status | Successor named by upstream |
|---|---|---|
| `design-an-interface` | **removed** | `/codebase-design` — the "design it twice" technique (parallel sub-agents, from Ousterhout) now ships *inside* it as `DESIGN-IT-TWICE.md` |
| `qa` | **removed** | `/triage` + `/to-tickets` |
| `request-refactor-plan` | **removed** | `/to-spec` + `/improve-codebase-architecture` |
| `obsidian-vault` | **removed** | none — "only ever mine… hardcoded a path to my own Obsidian vault". The `personal/` bucket was deleted with it |
| `ubiquitous-language` | **removed** | `/domain-modeling`, "which builds and maintains the whole domain model rather than dumping a glossary from one conversation" |
| `edit-article` | **removed** | none — "only ever mine" |
| `writing-great-skills` | **renamed** | `writing-for-agents` (PR #766 fixes the stale `interface.display_name` that "still named the old `writing-great-skills` skill") |
| `planning-with-files` | **never upstream** | see §6.4 |

Correction to the obvious assumption: the newer upstream skills are **already on this box**, not
missing from it. `~/.agents/skills/` contains `ask-matt`, `grill-me`, `grill-with-docs`,
`implement`, `improve-codebase-architecture`, `setup-matt-pocock-skills`, `teach`, `to-spec`,
`to-tickets`, `triage`, `wayfinder`, `wizard`, `handoff`, plus the `in-progress/` beta channel
(`claude-handoff`, `loop-me`, `writing-beats`, `writing-fragments`, `writing-shape`). None of them
is advertised in the current listing. Absent from disk: `to-questionnaire`, `wait-what`,
`implement-spec`, `retro`, `setup-ts-deep-modules`, `writing-for-agents`. So the cull was a
*listing* decision, not a deletion — the bytes are all still there, including the seven skills
upstream has since deleted or renamed.

Behavioural drift, measured by fetching each upstream `SKILL.md` and comparing to the on-disk copy:

| Skill | On disk | Upstream `main` | Drift |
|---|---|---|---|
| `diagnosing-bugs` | 8 670 B, **no** `redact` match | 8 526 B, **has** Redact section | **Stale — the security-relevant one** |
| `grilling` | 833 B, **no** `frontier` match | 1 975 B, **has** frontier rework | **Stale — 2.4× rewritten** |
| `code-review` | — | 6 559 B | changed by PR #781 + #734 (see below) |
| `codebase-design` | — | 6 066 B | changed by PR #781; now carries `DESIGN-IT-TWICE.md` |
| `tdd` | — | 3 541 B | no notable CHANGELOG entry |

The two that matter, from the CHANGELOG:
- `diagnosing-bugs` gained a **Redact** section (PR #779, v1.2.3): `<REDACTED>` is the first move
  on every command, output and captured artifact; loops are built against env vars "so the
  credential stays in the environment"; Phase 1 now asks the user for a *redacted* artifact, and
  `scripts/hitl-loop.template.sh` notes that `capture` echoes its value back to the terminal.
  **For an E2EE messenger repo whose diagnosis loop touches keys and tokens, this is the single
  most valuable upstream change in the set — and the on-disk copy does not contain it.**
- `grilling` was reworked **one-question-at-a-time → round-by-round** (PR #593): it maps the
  decision tree and asks the whole *frontier* — every question whose prerequisites are settled —
  in one numbered round, ~3 rounds instead of 13, in a fixed `❓ **Q1** - **<title>**` / body /
  `➡️` shape, dispatching environment-answerable facts to background sub-agents. PR #532 also
  de-scoped it from software plans to any plan/decision/idea.

Two more changes that improve OMP fit without needing action:
- `code-review`, `codebase-design`, `improve-codebase-architecture` had **Claude Code tool and
  agent-type names dropped** from their subagent-dispatch steps (PR #781) "so the step is
  followable on Codex and other harnesses" — upstream is actively de-Claude-ifying.
- `code-review` renamed PRD → spec throughout (PR #734). v1.2.0 added `agents/openai.yaml` beside
  every `SKILL.md` and marked user-invoked skills `policy.allow_implicit_invocation: false`.

**Verdict: selectively re-pull, do not re-adopt the plugin.**
- **Pull the new `diagnosing-bugs` body** (redaction discipline) — highest value, zero new listing
  cost since the skill is already in the listing.
- **Pull the new `grilling` body** (round-by-round) — same reasoning; the local `grilling` is a
  strictly worse version of a skill that's already costing budget.
- **Delete, don't retire, the seven upstream-deleted/renamed dirs** — `design-an-interface`, `qa`,
  `request-refactor-plan`, `obsidian-vault`, `ubiquitous-language`, `edit-article`,
  `writing-great-skills`. Four of them (`design-an-interface`, `qa`, `request-refactor-plan`,
  `obsidian-vault`) are still in the advertised 18, so they are costing listing budget *today* for
  guidance their own author has withdrawn. `obsidian-vault` hardcodes a path to someone else's
  Obsidian vault.
- **Do not install the plugin**: the two-level layout defeats OMP discovery, and 25 skills would
  roughly double the listing tax for skills this repo doesn't use (`to-tickets`, `wizard`,
  `teach`, `to-questionnaire`, `ask-matt`).

### 6.4 `planning-with-files` provenance — **already have; upstream is `OthmanAdi/planning-with-files`**

- **Provenance:** `OthmanAdi/planning-with-files`, **MIT**, 26 813★, `pushed_at`
  2026-09-09T22:00:02Z, topic `claude-skills`; description "Persistent file-based planning for AI
  coding agents and long-running tasks. Crash-proof ma[nus-style]…" — matches the on-box skill,
  which is one of only three skills on this box that ship supporting files (`init-session.{sh,ps1}`,
  `gate-stop.sh`, `attest-plan.{sh,ps1}`, `ledger-append.{sh,ps1}`, `phase-status.{sh,ps1}`,
  `check-complete.{sh,ps1}`, `session-catchup.py`, plus `templates/`, `examples.md`,
  `reference.md` — 26 files). The other two are `diagnosing-bugs` and
  `git-guardrails-claude-code`. It is also one of only two real directories under
  `~/.claude/skills/` rather than a symlink, i.e. a vendored copy.
- **Fit verdict: already have; note the Windows hazard.** It ships paired `.sh`/`.ps1` for every
  script, which is the right shape for Windows 11 — but `gate-stop.sh` has no `.ps1` twin, and its
  name says it is a `Stop`-hook gate. Under OMP there is no Stop equivalent (§4.2) and under
  Windows a bare `.sh` needs Git Bash. **The plan-gating half of this skill does not work on this
  box.** The file-based planning half (task_plan/findings/progress) does, and is the part this repo
  uses. No action beyond knowing the gate is decorative here.

### 6.5 High-star generic collections — **do not install**

Searched `topic:agent-skills` and `topic:claude-skills` sorted by stars. Everything above 30 k★
that isn't already covered:

| Repo | ★ | License | `pushed_at` | Why not |
|---|---|---|---|---|
| `addyosmani/agent-skills` | 93 586 | MIT | 2026-09-12 | 25 process skills (`spec-driven-development`, `doubt-driven-development`, `constraint-driven-development`, `source-driven-development`, `context-engineering`, `test-driven-development`, `frontend-ui-engineering`, …). Real named author, active, ships `hooks/`, `evals/`, `agents/`, per-harness dirs. **Closest thing to a credible general engineering set** — but it is ~25 more descriptions of methodology this repo already has opinions about, four of them near-identical "X-driven-development" variants. Methodology-by-listing is exactly the budget sink §4.1 warns about. |
| `DietrichGebert/ponytail` | 135 910 | MIT | 2026-09-07 | "Makes your AI agent think like the laziest senior dev in the room" — a taste/verbosity prior. Duplicates this repo's own standards. |
| `thedotmack/claude-mem` | 93 703 | Apache-2.0 | 2026-09-11 | Persistent cross-session memory. Directly duplicates OMP's native `memory`/`mnemosyne` backend and `learn`/`manage_skill`. Adding a second memory system is the "second convention beside an existing one" failure. |
| `nexu-io/open-design` | 95 648 | Apache-2.0 | 2026-09-12 | Design plugin, positioned as a "DeepSeek Harness"/Claude Design alternative. Web-shaped; §3.3 covers this need natively. |
| `Egonex-AI/Understand-Anything` | 82 074 | MIT | 2026-09-11 | Code→knowledge-graph. This is the same class as **graphify**, removed 2026-09-10 for 1.8 % Dart edge precision. No reason to expect better Dart parsing from a generic grapher. **Explicitly re-rejected.** |
| `tt-a1i/archify` | 58 700 | MIT | 2026-09-12 | Architecture/sequence/data-flow diagram skill. Marginal: this repo does want diagrams, and the harness renders mermaid natively — so the skill adds a listing cost for something already available. |
| `blader/humanizer` | 46 986 | MIT | 2026-09-06 | De-AI-ifies prose. Not a coding need. |
| `ayghri/i-have-adhd` | 42 112 | MIT | 2026-09-10 | Output-shape prior ("stop burying the answer"). Belongs in CLAUDE.md as a fact, not a skill. |
| `K-Dense-AI/scientific-agent-skills` | 44 490 | MIT | 2026-09-12 | Science domain. Off-stack. |
| `VoltAgent/awesome-agent-skills`, `VoltAgent/awesome-openclaw-skills`, `ComposioHQ/awesome-claude-skills`, `hesreallyhim/awesome-claude-code`, `travisvn/awesome-claude-skills`, `alirezarezvani/claude-skills`, `sickn33/agentic-awesome-skills` | 15 k–75 k | mixed / `travisvn` unlicensed, `travisvn` last pushed **2026-04-28** | — | Link farms and bulk re-hosts ("1000+ skills", "380 skills", "5 400+ filtered"). Aggregate star counts are not per-skill provenance. **Not evidence of anything; excluded.** |
| `wshobson/agents` | 39 575 | MIT | 2026-09-07 | Multi-harness agent marketplace; overlaps OMP's own agent/marketplace layer. |
| `github/awesome-copilot` | 38 914 | MIT | 2026-09-11 | Copilot-targeted. |
| `yusufkaraaslan/Skill_Seekers` | 14 955 | MIT | 2026-09-06 | Converts docs sites/repos/PDFs into skills. Interesting generator, but the output is exactly the bulk-skill bloat §4.1 penalises. |
| `titanwings/distilly` | 24 633 | MIT | 2026-09-11 | Distils transcripts into skills. Same objection; OMP's `learn` already does the in-harness version. |

---

## 7. July-audit re-checks (material changes only)

Per instruction I only re-checked for archival / licence / release changes since July:

| Item | Status now | Changed since July? |
|---|---|---|
| GitHub MCP (previously rejected: `gh` covers it) | Still vendored at `external_plugins/github/` in the official marketplace | **No material change.** Rejection stands; this survey's own data collection was done entirely with `gh api`, which is the proof. |
| graphify (removed 2026-09-10, Dart edges 1.8 % precision) | Same class re-appeared as `Egonex-AI/Understand-Anything` (82 k★) | **No** — re-rejected on the same grounds (§6.5) |
| Sentry self-hosted (needs 16 GB) | Not surveyed here (not a skill/plugin) | n/a |
| Postgres reference MCP (archived 2025-05-28) | Not surveyed here | n/a |
| Dart MCP (mounted, on probation) | `kevmoo/dash_skills` is adjacent but complementary, not a replacement (§3.1) | **No change to probation** |

---

## 8. Verdict roll-up

**Install (3):**
1. `skill-creator@claude-plugins-official` — the only primary-source way to measure whether a
   skill's description triggers and whether its body earns its tokens. Bytes already cached on box.
2. `kevmoo/dash_skills`, **partial** — `dart-test-fundamentals`, `dart-matcher-best-practices`,
   `dart-test-coverage`, `profile-dart-code`, via `skills.customDirectories` (pin a SHA; no tags).
3. Re-pull upstream bodies for **`diagnosing-bugs`** (8 670 B on disk with no redaction section →
   8 526 B upstream with one; E2EE repo) and **`grilling`** (833 B → 1 975 B round-by-round
   rework) from `mattpocock/skills` v1.2.3. Zero new listing cost — both are already listed.

**Already have / no action (5):** `code-review` and `claude-md-management` plugins are both current
(zero upstream commits since April; the `"unknown"` version is a missing field, not a stale
install). `flutter-frontend-design` has no upstream to track and beats every surveyed Flutter
skill. `umbra-session-end` has no mature equivalent and its pre-commit gate is a stronger
enforcement mechanism than any harness hook. OMP's built-in `/handoff` covers the
conversation-portability half.

**Do not install (everything else), with the three reasons that decide most of them:**
hooks-only value (inert under OMP): `security-guidance`, `ralph-loop`, `hookify`, `superpowers`'
bootstrap. Reads `~/.claude/projects` (empty here): `session-report`, `receipts`. Duplicates
something the harness or repo already has: `frontend-design`, `claude-mem`, `archify`,
`addyosmani/agent-skills`, most of `superpowers`.

**Cleanup, no install needed (5):**
- Run `/skill-doctor` under `claude -p` and set never-invoked entries to `"name-only"` in
  `skillOverrides`. 18 skills are taxing every turn.
- **Delete the 7 upstream-deleted/renamed dirs** in `~/.agents/skills/`: `design-an-interface`,
  `qa`, `request-refactor-plan`, `obsidian-vault`, `ubiquitous-language`, `edit-article`,
  `writing-great-skills`. Four are in the advertised 18 today.
- **Do not "de-duplicate" `~/.claude/skills/`** — its entries are symlinks into
  `~/.agents/skills/`, and both harnesses dedup by target/`realpath`. This looks like redundancy
  and isn't. Verified with `readlink`.
- Delete the 6 orphaned plugin cache dirs and 5 empty `plugins/data/*-inline/` dirs under
  `~/.claude/plugins/`.
- Decide whether `flutter-frontend-design` should move from `~/.claude/skills/` into the repo so it
  is versioned and reaches cloud sessions.

**Authoring rule to adopt (costs nothing):** keep every repo skill's frontmatter to
`name` + `description` (+ `disable-model-invocation` when manual-only). That is the only
intersection of the Agent Skills six-field spec, the Skills-API validator, and OMP's reader.
Never rely on `!`command``, `${CLAUDE_*}`, `context: fork`, or `allowed-tools` in a skill that must
work under OMP.

---

## Sources

Every URL below was read directly for this file.

GitHub API (authenticated `gh api`, 2026-09-12):
- `https://api.github.com/repos/anthropics/claude-plugins-official`
- `https://api.github.com/repos/anthropics/claude-plugins-official/contents/` (+ `/plugins`, `/external_plugins`)
- `https://api.github.com/repos/anthropics/claude-plugins-official/commits?path=plugins/<name>&per_page=1` (all 39 first-party plugins)
- `https://api.github.com/repos/anthropics/claude-plugins-official/commits?path=plugins/<name>&since=2026-04-15T00:00:00Z&per_page=100` (all 39)
- `https://api.github.com/repos/anthropics/skills` (+ `/contents/`, `/contents/skills`, `/contents/spec`)
- `https://api.github.com/repos/obra/superpowers` (+ `/contents/`, `/contents/skills`, `/contents/hooks`, `/contents/.pi`, `/contents/.pi/extensions`, `/releases`)
- `https://api.github.com/repos/mattpocock/skills` (+ `/contents/`, `/contents/skills`, `/contents/skills/{engineering,productivity,misc,deprecated,in-progress}`, `/releases`)
- `https://api.github.com/repos/can1357/oh-my-pi` (+ `/contents/docs`)
- `https://api.github.com/repos/kevmoo/dash_skills` (+ `/contents/`, `/contents/skills`, `/contents/plugins`, `/releases`)
- `https://api.github.com/users/kevmoo`
- `https://api.github.com/repos/addyosmani/agent-skills` (+ `/contents/`, `/contents/skills`)
- `https://api.github.com/search/repositories?q=topic:agent-skills&sort=stars&order=desc&per_page=15`
- `https://api.github.com/search/repositories?q=topic:claude-skills&sort=stars&order=desc&per_page=15`
- `https://api.github.com/search/repositories?q=flutter+skills+in:name,description+topic:agent-skills&sort=stars`
- `https://api.github.com/search/repositories?q=flutter+agent+skills+claude+in:name,description&sort=stars`
- `https://api.github.com/search/repositories?q=dart+flutter+claude-skills+in:name,description&sort=stars`
- `https://api.github.com/search/repositories?q=flutter-frontend-design&sort=stars`
- `https://api.github.com/search/code?q=flutter-frontend-design+in:path`

Raw files:
- `https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json`
- `https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/plugins/<name>/.claude-plugin/plugin.json` (`security-guidance`, `claude-security`, `code-modernization`, `frontend-design`, `code-review`, `claude-md-management`, `session-report`, `skill-creator`, `hookify`, `plugin-dev`)
- `https://raw.githubusercontent.com/anthropics/skills/main/spec/agent-skills-spec.md`
- `https://raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md`
- `https://raw.githubusercontent.com/obra/superpowers/main/.claude-plugin/plugin.json`
- `https://raw.githubusercontent.com/obra/superpowers/main/hooks/hooks.json`
- `https://raw.githubusercontent.com/obra/superpowers/main/README.md`
- `https://raw.githubusercontent.com/obra/superpowers/main/.pi/extensions/superpowers.ts`
- `https://raw.githubusercontent.com/mattpocock/skills/main/package.json`
- `https://raw.githubusercontent.com/mattpocock/skills/main/.claude-plugin/plugin.json`
- `https://raw.githubusercontent.com/mattpocock/skills/main/CHANGELOG.md`
- `https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/handoff/SKILL.md`
- `https://raw.githubusercontent.com/can1357/oh-my-pi/main/README.md`
- `https://raw.githubusercontent.com/can1357/oh-my-pi/main/docs/hooks.md`
- `https://raw.githubusercontent.com/can1357/oh-my-pi/main/docs/skills.md`
- `https://raw.githubusercontent.com/can1357/oh-my-pi/main/docs/handoff-generation-pipeline.md`
- `https://raw.githubusercontent.com/charansaikondilla/ceomans/main/.claude/skills/flutter-frontend-design/SKILL.md`
- `https://raw.githubusercontent.com/mattpocock/skills/main/skills/engineering/{diagnosing-bugs,code-review,codebase-design,tdd}/SKILL.md` (byte-size / content comparison against the on-disk copies)
- `https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grilling/SKILL.md`

Official docs:
- `https://docs.claude.com/en/docs/claude-code/skills` → resolves to `https://code.claude.com/docs/en/skills`
- `https://code.claude.com/docs/en/hooks`

Local files (this machine, read-only):
- `C:\Users\Lentach\.claude\plugins\installed_plugins.json`
- `C:\Users\Lentach\.claude\skills\flutter-frontend-design\SKILL.md`
- `.omp/skills/umbra-session-end/SKILL.md`
- Directory listings and `SKILL.md` counts for `C:\Users\Lentach\.agents\skills\` (39),
  `C:\Users\Lentach\.claude\skills\` (12), `.omp\skills\` (1), plus
  `C:\Users\Lentach\.omp\skills\` (empty) and `C:\Users\Lentach\.codex\skills\` (`.system` only)
- `C:\Users\Lentach\.claude\plugins\` tree (cache, marketplaces, `data/*-inline/`)
- Byte sizes and `grep` content checks on `~/.agents/skills/{diagnosing-bugs,grilling}/SKILL.md`
  against their upstream equivalents; `readlink` on every `~/.claude/skills/` entry to establish
  which are symlinks into `~/.agents/skills/` and which are real directories
