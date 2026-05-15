---
inclusion: always
---

# Superpowers (ported to Kiro steering)

This workspace has the Superpowers methodology available as steering files, ported from https://github.com/obra/superpowers (MIT license, by Jesse Vincent and the Prime Radiant team).

Each skill below is a separate steering file with `inclusion: manual`. Pull one into context by referencing it with `#<filename>` in chat when the situation calls for it.

## Available skills

- `#superpowers-brainstorming.md` — Use before any creative/implementation work. Explores intent, requirements, and design before code. Produces a design doc.
- `#superpowers-writing-plans.md` — Use when you have a spec and need a bite-sized, TDD-oriented implementation plan.
- `#superpowers-tdd.md` — Use when implementing any feature or bugfix. Enforces RED → GREEN → REFACTOR.
- `#superpowers-debugging.md` — Use for any bug, test failure, or unexpected behavior. Four-phase systematic root-cause process.
- `#superpowers-verification.md` — Use before claiming work is complete. Evidence before assertions.

## The canonical flow

1. **Brainstorm** the idea into a design (`superpowers-brainstorming`)
2. **Plan** the design into tasks (`superpowers-writing-plans`)
3. **Implement** each task with TDD (`superpowers-tdd`)
4. **Debug** systematically when something breaks (`superpowers-debugging`)
5. **Verify** before claiming done (`superpowers-verification`)

## How I should behave by default

- When the user asks me to build, add, or change something non-trivial, I should suggest pulling in `#superpowers-brainstorming.md` before writing code.
- When the user explicitly says "just do X" or the change is a one-line trivial edit, I proceed directly.
- When a bug or test failure shows up, I should suggest pulling in `#superpowers-debugging.md`.
- The user's explicit instructions always take precedence over these skills. If they say "skip TDD" or "no design doc", I follow that.

## Other ported Claude Code plugins (manual inclusion)

Separate from Superpowers. Pull in when relevant:

- `#claude-md-management.md` — Audit `CLAUDE.md` quality and capture session learnings as targeted diffs. Use at end of a productive session, or when project memory feels stale. Ported from https://claude.com/plugins/claude-md-management.
- `#frontend-design.md` — Design-first workflow for UI work: brief → tokens → layout moves → motion → detail pass → a11y. Forces non-generic output. Ported from https://claude.com/plugins/frontend-design. Tailored to Fireplace's Flutter + `FireplaceColors` setup.

## What's NOT ported from the original Superpowers

- Hooks and scripts (worktree automation, visual brainstorming companion, server lifecycle scripts). Those run on Claude Code / Codex / Cursor, not Kiro.
- Sub-skill files (`root-cause-tracing.md`, `defense-in-depth.md`, `condition-based-waiting.md`, `testing-anti-patterns.md`). The core `SKILL.md` content is ported; reach into the full repo at `C:\Users\Lentach\.kiro\powers\repos\superpowers\skills\` if you want the sub-skills too.
- Subagent-driven-development orchestration prompts. Kiro has its own `invoke_sub_agent` mechanism with different semantics.
