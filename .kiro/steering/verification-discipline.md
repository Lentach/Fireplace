---
inclusion: always
---

# Verification discipline

Before you tell the user "done", prove it. Evidence before assertions.

## Mandatory checks after meaningful changes

"Meaningful" = new feature, bugfix, refactor, API/env/schema change, security change, test change, dependency bump. Trivial one-line edits (typo, formatting) are exempt.

Run whichever of these apply to what you touched. Commands live in `CLAUDE.md` — if they drift here, `CLAUDE.md` wins.

- **Backend change** (`backend/**`): `cd backend && npm test`
- **Frontend change** (`frontend/**`): `cd frontend && flutter analyze` **and** `cd frontend && flutter test`
- **Shared / repo-wide change**: run both suites
- **Before deleting any "unused" symbol in Flutter**: `cd frontend && flutter analyze` — the repo has real-but-analyzer-unfriendly call sites (`clearStatus()` in `AuthProvider` is the canonical trap)
- **Docs-only change** (`*.md`, no code): no test run required, but still state that explicitly

## Reporting format

In the final message that closes the task, include a short `Verification` block:

```
Verification
- cd backend && npm test — 277 passed, 39 suites (CI: `node scripts/verify-claude-backend-test-counts.mjs`)
- cd frontend && flutter analyze — no issues
- cd frontend && flutter test — 115 passed
```

If a check was **not** run, say so and why (e.g. "skipped `flutter test` — change is backend-only"). If a check **failed**, fix it before declaring done; do not ship red.

## What this rule forbids

- "Should work" / "looks correct" without running the suite.
- Running only a single targeted test when the change crosses module boundaries.
- Deleting "unused" code without `flutter analyze` evidence.
- Committing with known analyzer warnings or failing tests unless the user has explicitly accepted them.

## Interaction with Superpowers

This rule is the always-on floor. The fuller TDD / verification methodology lives in `#superpowers-tdd.md` and `#superpowers-verification.md` — pull those in for larger or more ambiguous work.
