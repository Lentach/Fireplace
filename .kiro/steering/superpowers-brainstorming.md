---
inclusion: manual
---

# Brainstorming (Superpowers skill, ported)

> Ported from https://github.com/obra/superpowers (MIT). Pull this into context with `#superpowers-brainstorming.md` when starting any non-trivial feature or change.

**Purpose:** Turn ideas into fully formed designs through natural collaborative dialogue, BEFORE writing code.

## Hard gate

Do NOT write code, scaffold a project, or take any implementation action until a design has been presented and the user has approved it. This applies to every project regardless of perceived simplicity.

## Anti-pattern: "This is too simple to need a design"

Every project goes through this process. A todo list, a single-function utility, a config change — all of them. Simple projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple projects), but you MUST present it and get approval.

## Checklist

Complete these in order:

1. **Explore project context** — check files, docs, recent commits
2. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
3. **Propose 2-3 approaches** — with trade-offs and a recommendation
4. **Present design** — in sections scaled to their complexity, get approval after each section
5. **Write design doc** — save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and commit
6. **Spec self-review** — scan for placeholders, contradictions, ambiguity, scope
7. **User reviews the written spec** — before proceeding
8. **Transition to implementation** — pull in `#superpowers-writing-plans.md`

## The process

**Understanding the idea**

- Check the current project state first (files, docs, recent commits)
- If the request describes multiple independent subsystems, flag this immediately. Don't refine details of a project that needs to be decomposed first.
- For appropriately-scoped projects, ask questions one at a time
- Prefer multiple-choice over open-ended when possible
- One question per message
- Focus on: purpose, constraints, success criteria

**Exploring approaches**

- Propose 2-3 different approaches with trade-offs
- Lead with a recommendation and explain why

**Presenting the design**

- Scale each section to its complexity (a few sentences up to ~200-300 words)
- Ask after each section whether it looks right
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify

**Design for isolation and clarity**

- Break the system into smaller units with one clear purpose and well-defined interfaces
- For each unit, answer: what does it do, how do you use it, what does it depend on
- Smaller, well-bounded units are easier to reason about and edit reliably
- Large files are often a signal the unit is doing too much

**Working in existing codebases**

- Explore the current structure before proposing changes; follow existing patterns
- Where existing code has problems that affect the work, include targeted improvements as part of the design
- Don't propose unrelated refactoring

## After the design

**Documentation**

- Write the validated spec to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Commit it to git

**Spec self-review**

1. Placeholder scan: any "TBD", "TODO", incomplete sections, vague requirements? Fix them.
2. Internal consistency: do sections contradict each other? Does the architecture match the feature descriptions?
3. Scope check: focused enough for a single plan, or does it need decomposition?
4. Ambiguity check: could any requirement be interpreted two ways? Pick one and make it explicit.

**User review gate**

Ask the user to review the written spec before proceeding:

> "Spec written and committed to `<path>`. Please review it and let me know if you want changes before we start writing the implementation plan."

Wait for the user's response. If they request changes, make them and re-run the spec review. Only proceed once approved.

**Implementation**

- Pull in `#superpowers-writing-plans.md` to produce the plan
- Do NOT jump straight to code

## Key principles

- One question at a time
- Multiple choice preferred
- YAGNI ruthlessly
- Explore alternatives (2-3 approaches minimum)
- Incremental validation — approval after each section
- Be flexible — go back when something doesn't make sense
