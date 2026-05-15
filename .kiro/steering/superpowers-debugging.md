---
inclusion: manual
---

# Systematic Debugging (Superpowers skill, ported)

> Ported from https://github.com/obra/superpowers (MIT). Pull this into context with `#superpowers-debugging.md` for any bug, test failure, or unexpected behavior.

## Overview

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**Core principle:** Find root cause before attempting fixes. Symptom fixes are failure.

## The iron law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If Phase 1 isn't complete, no fixes yet.

## When to use

Any technical issue: test failures, bugs in production, unexpected behavior, performance problems, build failures, integration issues.

Especially when:

- Under time pressure
- "Just one quick fix" seems obvious
- You've tried multiple fixes already
- Previous fix didn't work
- You don't fully understand the issue

## The four phases

### Phase 1 — Root cause investigation

1. **Read error messages carefully.** Don't skip past errors or warnings. They often contain the exact solution. Read stack traces completely.

2. **Reproduce consistently.** Can you trigger it reliably? Exact steps? Every time? If not reproducible, gather more data — don't guess.

3. **Check recent changes.** Git diff, recent commits, new dependencies, config changes, environmental differences.

4. **Gather evidence in multi-component systems.** When the system has multiple components (CI → build → signing, API → service → database):

   Before proposing fixes, add diagnostic instrumentation:
   - For each component boundary, log what data enters and exits
   - Verify environment/config propagation
   - Check state at each layer
   - Run once to gather evidence showing WHERE it breaks
   - Analyze the evidence to identify the failing component
   - Investigate that specific component

5. **Trace data flow.** When the error is deep in the call stack: where does the bad value originate? What called this with a bad value? Keep tracing up until you find the source. Fix at the source, not at the symptom.

### Phase 2 — Pattern analysis

1. **Find working examples.** Locate similar working code in the same codebase.
2. **Compare against references.** If implementing a pattern, read the reference implementation completely. Don't skim.
3. **Identify differences.** Every difference, however small. Don't assume "that can't matter".
4. **Understand dependencies.** What other components does this need? Settings? Config? Environment? Assumptions?

### Phase 3 — Hypothesis and testing

1. **Form a single hypothesis.** "I think X is the root cause because Y." Write it down. Be specific.
2. **Test minimally.** Smallest possible change to test the hypothesis. One variable at a time. Don't fix multiple things at once.
3. **Verify before continuing.** Worked? → Phase 4. Didn't work? → New hypothesis. Don't stack fixes.
4. **When you don't know, say so.** Don't pretend. Ask or research.

### Phase 4 — Implementation

1. **Create a failing test case.** Simplest possible reproduction. Automated test if possible, one-off script if no framework. Must exist before fixing. Pull in `#superpowers-tdd.md` for writing it properly.
2. **Implement a single fix.** Address the root cause. One change at a time. No "while I'm here" improvements.
3. **Verify the fix.** Test passes? No other tests broken? Issue actually resolved?
4. **If the fix doesn't work, stop.** Count fixes tried. If < 3, return to Phase 1 and re-analyze. If ≥ 3, stop and question the architecture.

5. **If 3+ fixes failed, question the architecture.**

   Pattern indicating an architectural problem:
   - Each fix reveals new shared state/coupling/problems elsewhere
   - Fixes require "massive refactoring" to implement
   - Each fix creates new symptoms elsewhere

   Stop and ask: is this pattern fundamentally sound? Are we sticking with it through inertia? Should we refactor the architecture instead of continuing to fix symptoms? Discuss with the user before attempting more fixes. This is not a failed hypothesis — this is a wrong architecture.

## Red flags — stop and follow the process

- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "Skip the test, I'll manually verify"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Pattern says X but I'll adapt it differently"
- Proposing solutions before tracing data flow
- "One more fix attempt" when already tried 2+
- Each fix reveals a new problem in a different place

## User signals you're doing it wrong

- "Is that not happening?" — you assumed without verifying
- "Will it show us…?" — you should have added evidence gathering
- "Stop guessing" — you're proposing fixes without understanding
- "Ultrathink this" — question fundamentals, not just symptoms
- Frustrated "We're stuck?" — your approach isn't working

When you see any of these: stop, return to Phase 1.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "Issue is simple, don't need process" | Simple issues have root causes too. Process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is faster than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I'll write a test after confirming the fix" | Untested fixes don't stick. Test first proves it. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
| "Reference too long, I'll adapt the pattern" | Partial understanding guarantees bugs. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "One more fix attempt" after 2+ failures | 3+ failures = architectural problem. Question the pattern. |

## Quick reference

| Phase | Key activities | Success criteria |
|---|---|---|
| 1. Root cause | Read errors, reproduce, check changes, gather evidence | Understand WHAT and WHY |
| 2. Pattern | Find working examples, compare | Identify differences |
| 3. Hypothesis | Form theory, test minimally | Confirmed or new hypothesis |
| 4. Implementation | Create test, fix, verify | Bug resolved, tests pass |

## When the process reveals "no root cause"

If systematic investigation reveals the issue is truly environmental, timing-dependent, or external:

1. You've completed the process
2. Document what you investigated
3. Implement appropriate handling (retry, timeout, error message)
4. Add monitoring/logging for future investigation

But: 95% of "no root cause" cases are incomplete investigation.
