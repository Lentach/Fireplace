---
inclusion: manual
---

# Writing Plans (Superpowers skill, ported)

> Ported from https://github.com/obra/superpowers (MIT). Pull this into context with `#superpowers-writing-plans.md` once a design/spec exists and you need an implementation plan.

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for this codebase and questionable taste. Document everything they need: which files to touch, the actual code, how to test it, commands to run, expected output. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume the engineer is skilled but knows almost nothing about the toolset or problem domain, and doesn't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`

## Scope check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking it into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file has one clear responsibility.
- Smaller, focused files are easier to reason about and edit reliably. Large files often signal a unit is doing too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. Don't unilaterally restructure — but if a file you're modifying has grown unwieldy, a targeted split is reasonable.

## Bite-sized task granularity

Each step is one action (2-5 minutes):

- "Write the failing test" — step
- "Run it to make sure it fails" — step
- "Implement minimal code to pass" — step
- "Run tests to make sure they pass" — step
- "Commit" — step

## Plan document header

Every plan starts with this header:

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## No placeholders

Every step must contain the actual content an engineer needs. These are plan failures — never write them:

- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" without actual test code
- "Similar to Task N" — repeat the code; the engineer may be reading tasks out of order
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Remember

- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, TDD, frequent commits

## Self-review

After writing the plan, look at the spec with fresh eyes and check the plan against it.

1. **Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.
2. **Placeholder scan:** Search the plan for the red flags above. Fix them.
3. **Type consistency:** Do the types, signatures, and property names in later tasks match earlier tasks? `clearLayers()` in Task 3 vs `clearFullLayers()` in Task 7 is a bug.

Fix issues inline. If you find a spec requirement with no task, add the task.

## Execution handoff

After saving the plan, present it and ask the user how they want to execute it (one task at a time with review, batched execution, fully autonomous, etc). Adapt to their preference.
