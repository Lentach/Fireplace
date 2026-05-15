---
inclusion: manual
---

# Verification Before Completion (Superpowers skill, ported)

> Ported from https://github.com/obra/superpowers (MIT). Pull this into context with `#superpowers-verification.md` before claiming any work is complete, fixed, or passing.

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

## The iron law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The gate function

Before claiming any status or expressing satisfaction:

1. **Identify** what command proves this claim
2. **Run** the full command (fresh, complete)
3. **Read** the full output, check the exit code, count failures
4. **Verify** the output confirms the claim — if not, state actual status with evidence; if yes, state the claim with evidence
5. **Only then** make the claim

Skip any step = lying, not verifying.

## Common failures

| Claim | Requires | Not sufficient |
|---|---|---|
| Tests pass | Test command output, 0 failures | Previous run, "should pass" |
| Linter clean | Linter output, 0 errors | Partial check, extrapolation |
| Build succeeds | Build command, exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Red flags — stop

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!")
- About to commit/push/PR without verification
- Trusting agent success reports without checking
- Relying on partial verification
- Thinking "just this once"
- Tired and wanting to be done
- Any wording implying success without having run verification

## Rationalization prevention

| Excuse | Reality |
|---|---|
| "Should work now" | Run the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "Partial check is enough" | Partial proves nothing |
| "Different words so the rule doesn't apply" | Spirit over letter |

## Key patterns

**Tests**

- ✅ Run test command → see `34/34 pass` → "All tests pass"
- ❌ "Should pass now" / "Looks correct"

**Regression tests (TDD red-green)**

- ✅ Write → run (pass) → revert fix → run (must fail) → restore → run (pass)
- ❌ "I've written a regression test" without the red-green verification

**Build**

- ✅ Run build → exit 0 → "Build passes"
- ❌ "Linter passed" (linter doesn't check compilation)

**Requirements**

- ✅ Re-read plan → create checklist → verify each → report gaps or completion
- ❌ "Tests pass, phase complete"

**Agent delegation**

- ✅ Sub-agent reports success → check VCS diff → verify changes → report actual state
- ❌ Trust the sub-agent's report

## When to apply

Always, before:

- Any variation of success/completion claims
- Any expression of satisfaction
- Any positive statement about work state
- Commits, PR creation, task completion
- Moving to the next task
- Delegating to sub-agents

Applies to exact phrases, paraphrases, synonyms, and any communication suggesting completion or correctness.

## The bottom line

Run the command. Read the output. Then claim the result. This is non-negotiable.
