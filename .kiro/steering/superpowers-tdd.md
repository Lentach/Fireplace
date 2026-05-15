---
inclusion: manual
---

# Test-Driven Development (Superpowers skill, ported)

> Ported from https://github.com/obra/superpowers (MIT). Pull this into context with `#superpowers-tdd.md` when implementing any feature or bugfix.

## Overview

Write the test first. Watch it fail. Write minimal code to pass.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

## When to use

Always, for:

- New features
- Bug fixes
- Refactoring
- Behavior changes

Exceptions (ask the user first):

- Throwaway prototypes
- Generated code
- Configuration files

## The iron law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote code before the test? Delete it. Start over.

No exceptions:

- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Don't look at it
- Delete means delete

## Red — Green — Refactor

### RED — write failing test

Write one minimal test showing what should happen.

Good:

```typescript
test('retries failed operations 3 times', async () => {
  let attempts = 0;
  const operation = () => {
    attempts++;
    if (attempts < 3) throw new Error('fail');
    return 'success';
  };

  const result = await retryOperation(operation);

  expect(result).toBe('success');
  expect(attempts).toBe(3);
});
```

Bad — vague name, tests mock instead of code:

```typescript
test('retry works', async () => {
  const mock = jest.fn()
    .mockRejectedValueOnce(new Error())
    .mockRejectedValueOnce(new Error())
    .mockResolvedValueOnce('success');
  await retryOperation(mock);
  expect(mock).toHaveBeenCalledTimes(3);
});
```

Requirements: one behavior, clear name, real code (no mocks unless unavoidable).

### Verify RED — watch it fail

Mandatory. Never skip. Run the test and confirm:

- Test fails (not errors)
- Failure message is expected
- Fails because the feature is missing, not a typo

If the test passes, you're testing existing behavior. Fix the test.
If the test errors, fix the error and re-run until it fails correctly.

### GREEN — minimal code

Simplest code to pass. Don't add features, don't refactor unrelated code, don't "improve" beyond the test.

### Verify GREEN — watch it pass

Mandatory. Confirm:

- Test passes
- Other tests still pass
- Output is pristine (no errors, no warnings)

Test fails? Fix the code, not the test. Other tests fail? Fix them now.

### REFACTOR — clean up

After green only. Remove duplication, improve names, extract helpers. Keep tests green. Don't add behavior.

### Repeat

Next failing test for the next behavior.

## Why order matters

"I'll write tests after to verify it works." Tests written after code pass immediately. Passing immediately proves nothing — might test the wrong thing, might test implementation instead of behavior, might miss edge cases you forgot. You never saw it catch the bug. Test-first forces you to see the test fail, proving it actually tests something.

"Already manually tested all edge cases." Manual testing is ad-hoc. No record of what you tested, can't re-run when code changes, easy to forget cases under pressure. Automated tests are systematic.

"Deleting X hours of work is wasteful." Sunk cost fallacy. The time is gone. Choice now: delete and rewrite with TDD (high confidence), or keep it and add tests after (low confidence, likely bugs). Working code without real tests is technical debt.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Already manually tested" | Ad-hoc ≠ systematic. |
| "Keep as reference, write tests first" | You'll adapt it. That's testing after. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "Test hard = design unclear" | Listen to the test. Hard to test = hard to use. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "Existing code has no tests" | You're improving it. Add tests for existing code. |

## Red flags — stop and start over

- Code before test
- Test passes immediately
- Can't explain why the test failed
- Tests added "later"
- "Keep as reference" / "adapt existing code"
- "TDD is dogmatic, I'm being pragmatic"
- "This is different because…"

## Verification checklist

Before marking work complete:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing
- [ ] Each test failed for the expected reason (feature missing, not typo)
- [ ] Wrote minimal code to pass
- [ ] All tests pass
- [ ] Output pristine (no errors, warnings)
- [ ] Tests use real code (mocks only if unavoidable)
- [ ] Edge cases and errors covered

Can't check all boxes? You skipped TDD. Start over.

## When stuck

| Problem | Solution |
|---|---|
| Don't know how to test | Write the wished-for API first. Write the assertion. Ask the user. |
| Test too complicated | Design too complicated. Simplify the interface. |
| Must mock everything | Code too coupled. Use dependency injection. |
| Test setup huge | Extract helpers. Still complex? Simplify the design. |

## Debugging integration

Bug found? Write a failing test that reproduces it. Follow the TDD cycle. The test proves the fix and prevents regression. Never fix bugs without a test.

## Final rule

```
Production code → test exists and failed first
Otherwise → not TDD
```

No exceptions without the user's permission.
