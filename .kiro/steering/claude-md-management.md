---
inclusion: manual
---

# CLAUDE.md Management (ported to Kiro steering)

Kiro-port of the [CLAUDE.md Management](https://claude.com/plugins/claude-md-management) plugin (Anthropic). Two workflows: **audit** the quality of `CLAUDE.md`, and **revise** it with session learnings. Pull this file in with `#claude-md-management.md` when you want to tune project memory.

> In Fireplace, `CLAUDE.md` is always-on context via `fireplace-claude-md.md`. Keeping it accurate and concise directly affects every future agent turn.

## When to activate

- User says "audit my CLAUDE.md", "check if CLAUDE.md is up to date", "is CLAUDE.md still correct".
- End of a productive session with new learnings worth persisting (new bash command, env quirk, gotcha, pattern).
- After landing a feature that changed API, DB schema, ports, build steps, or security posture.
- Before starting a big refactor — bad memory produces bad plans.

## Workflow A — Audit

Goal: produce a scored report on `CLAUDE.md` (and any `.claude.local.md` / nested `CLAUDE.md`s) against quality criteria, then propose **targeted** additions and deletions. Apply only after user approves the diff.

### Step 1. Enumerate memory files

Search the repository for all memory files that end up in the agent's context:

- Repo root: `CLAUDE.md`
- Any `CLAUDE.md` or `.claude.local.md` inside subprojects (`backend/`, `frontend/`, `docs/`).
- Always-on Kiro steering files in `.kiro/steering/*.md` (those whose frontmatter is missing `inclusion: manual` / `inclusion: fileMatch`).

List them in the report with path + size in lines.

### Step 2. Score each file

Rate each memory file 1–5 on these axes. Show the numeric score and a one-line justification per axis.

| Axis | 1 (bad) | 5 (good) |
|---|---|---|
| **Commands** | No runnable commands; "run the app" | Exact `npm`, `flutter`, `docker`, shell commands with working dirs and flags |
| **Architecture** | Hand-wavy ("modular", "clean") | Concrete stack, ports, entry points, module boundaries, file map |
| **Gotchas** | Absent or generic best-practice | Real, specific, debugged-once-already traps (framework bugs, race conditions, platform quirks) |
| **Conciseness** | Long prose, repeated info, dead sections | Scannable, grouped, each fact earns its line |
| **Accuracy** | Contradicts current code, references deleted files | Matches HEAD; filenames, method names, env vars verified against source |
| **Scope** | Contains session narratives, chat logs, dated notes that belong in `/docs` | Only durable project rules |

### Step 3. Detect gaps

Cross-check against the codebase. Flag missing entries in these common buckets (only suggest when actually present in the repo):

- **Quick start** — how to run backend, frontend, tests, each on every supported platform.
- **Ports, env vars, feature flags** — especially anything non-default or platform-conditional.
- **Stack & versions** — framework majors, DB, auth, runtime.
- **File map / module boundaries** — where to put new code.
- **Framework gotchas** — ORM quirks, DI traps, async lifecycle, lifecycle hooks that run in unexpected order.
- **Platform gotchas** — web vs native, iOS vs Android, emulator vs device, Windows vs unix paths.
- **Security invariants** — what must stay true (auth, validation, rate limiting, SSRF, cascade deletes).
- **Test strategy** — how to run unit/widget/e2e, what CI does, test-only hooks or mocks.
- **Known-broken edges** — things that look fixable but are wontfix for a reason; link to the reason.
- **Release / deploy** — where prod is, how to deploy, how to roll back.

### Step 4. Detect rot

Surface anything that looks stale:

- References to files that no longer exist (`grep`-verify each filename mentioned).
- Method / class / gateway names that don't match source (`grepSearch` 3–5 random ones).
- Package versions that differ from `package.json` / `pubspec.yaml`.
- TODOs, "temporary notes", dated session logs — move to `/docs` or delete.
- Duplicate content repeated across sections or across parallel memory files.

### Step 5. Deliver the report

Format:

```
# CLAUDE.md audit — <date>

## Files reviewed
- CLAUDE.md (N lines)
- frontend/CLAUDE.md (N lines)      # if present
- .kiro/steering/*.md (always-on)    # listed

## Scores
| File | Commands | Architecture | Gotchas | Conciseness | Accuracy | Scope | Overall |
...

## Gaps (add)
- [ ] <one line>, suggested section: "X. Y"
  Why: <evidence: link to file or command output>
  Proposed diff:
  ```diff
  ...
  ```

## Rot (remove or update)
- [ ] <stale line>, file:line
  Evidence: <what's actually true now>
  Proposed diff: ...

## Scope leaks (move out)
- [ ] <content>, belongs in <path> instead of CLAUDE.md
```

**Do not** apply changes yet. Wait for user approval of individual items.

## Workflow B — Revise (capture learnings)

Goal: at end of a session, turn new concrete findings into durable lines in the right memory file.

### Step 1. Collect candidate learnings

Scan the current session for:

- Bash / flutter / npm commands that worked after several tries.
- Env vars, flags, `--dart-define`, `GRADLE_USER_HOME`-style quirks.
- Framework/platform behavior that surprised you (not the user's domain logic — that belongs in tests).
- Fixed bugs whose root cause is easy to re-hit (document the invariant that would have prevented it).
- Files/endpoints added/removed/renamed that invalidate an existing line in `CLAUDE.md`.
- Test commands, test-only hooks, CI steps that future sessions need to know.

### Step 2. Classify each candidate

For each learning, decide:

- **Durable rule for everyone** → repo root `CLAUDE.md`.
- **Per-subproject rule** → nearest `CLAUDE.md` under the subproject.
- **Local to this machine** → `.claude.local.md` (gitignored) — credentials, personal paths.
- **Narrative / one-off explanation** → `/docs` or a session summary, not memory files.
- **Workflow / method** → Kiro steering (`.kiro/steering/*.md`) with `inclusion: manual`, not `CLAUDE.md`.

### Step 3. Find the right section

Read the target file first, then insert under the most specific existing section. Prefer extending a bullet list to creating a new section. If you must add a section, match the numbering and heading style already in the file.

### Step 4. Write the line

A good `CLAUDE.md` line is:

- **One sentence** (two max, when the fact has a genuinely non-obvious "because").
- **Imperative or factual**, never narrative. "X does Y because Z" beats "we ran into an issue where…".
- **Names real symbols** — file paths, class names, method names — so an agent can `grep` them.
- **Has an invariant**, not just a story. Prefer "always X" / "never Y" / "X returns Z, not W".
- **No dates, no session IDs, no "today we fixed…"** — those go in session summaries.

### Step 5. Show diff, apply on approval

Present every edit as a unified diff grouped by file. Apply only with user approval, in the same turn.

## Guardrails

- **Never** silently rewrite large sections of `CLAUDE.md`. Targeted edits only, with diff, with justification.
- **Never** remove a "weird" line just because it looks out of place. Ask — it's probably there to prevent a specific regression (`clearStatus()` in `AuthProvider` is the canonical example in this repo).
- **Never** add duplicates. If a similar line already exists, extend it instead of adding a new one.
- **Always** verify filenames and symbol names against source before writing them into memory.
- **Respect Fireplace's rule from `fireplace-claude-md.md`:** project knowledge lives in `CLAUDE.md`, not in a parallel Cursor/Kiro long-form spec.

## Quick commands (user-facing)

The user doesn't have slash commands in Kiro, but these phrases trigger this workflow:

- "audit my CLAUDE.md" → run Workflow A end-to-end, stop at the report.
- "revise CLAUDE.md with today's learnings" → run Workflow B, stop at diffs.
- "apply the approved items" → apply the diffs the user ticked, nothing else.
