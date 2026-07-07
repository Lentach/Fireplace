# Agent Prompt Template (Fireplace)

Reusable structure for prompts handed to executing agents (Fable/Sonnet/Opus). Fill the
sections; delete what doesn't apply. The **meta-rules** at the bottom are non-negotiable and
should be reflected in every prompt.

CLAUDE.md is the source of truth for architecture/contracts — prompts reference it, never
restate it.

---

## Template

```text
# ROLE / CONTEXT
<Who the agent is + the relevant stack/subsystem in one short paragraph. Name the branch if the
work continues an existing one.>

# VERIFY FIRST (from source — confirm, don't assume; no guessed paths)
<What to read/locate before acting. The agent must open files and cite real file:line — never
state a path/line/behavior as fact unless verified this run.>

# OBJECTIVE  (bugs: + SYMPTOMS / EVIDENCE)
<One–two sentences on the end state. For bugs, list exact observed symptoms + any logs/screens,
and label hypotheses as hypotheses.>

# TASKS (in order)
<Ordered, testable steps. Reproduce → root-cause → fix → verify. Split compound work.>

# CONSTRAINTS
<Must-dos / must-not-dos. Always include: E2E invariant (server sees ciphertext/metadata only;
never log plaintext/keys), don't regress named working behavior, scope boundary.>

# DELIVERABLE  (definition of done — evidence, not assertions)
<Root-cause writeup (cited file:line), patch/diff, and VERIFICATION: pasted command output +
real-device matrix. "It works" without evidence is not done.>

# CLARIFY FIRST
<Only genuinely-open decisions the user must make. If none, say so.>

# WORKFLOW
<New feature branch (name it) + PR; small/trivial → master. Push in the same checkpoint.
Frontend live after merge + .\deploy-web.ps1; backend after merge + restart. Update CLAUDE.md
§ relevant.>

# REFERENCES
<Only genuinely-useful links (platform docs). For project facts, "read the repo/package", not a
web URL. Skip if none — don't pad.>
```

---

## Meta-rules (bake into every prompt)

1. **Verify before claiming.** No path/line/symbol/behavior stated as fact unless opened/run
   this turn. No guessed `file:line`. Unverified → say so or keep generic.
2. **Feasibility gate.** Classify code-bug vs platform-limit first. If it's an unfixable platform
   ceiling (iOS keyboard bounce, web-push tag/getNotifications limits, Android numeric badge,
   deep-Doze), say so and drop it — don't send an agent to chase it.
3. **Definition of done = evidence.** Real device matrix + pasted output. No "should work."
4. **E2E is sacred.** Never weaken encryption, log plaintext/keys, or clear localStorage/
   IndexedDB (Signal keys). Server stays blind.
5. **Scope discipline.** Fix only what's asked; flag adjacent issues, don't fold them in.
6. **Model tiering.** High-reasoning model for E2E/crypto/auth/security/intermittent root-cause;
   cheaper/faster model for well-scoped mechanical UI/layout/test work.
7. **Branch + PR** for substantial work; irreversible/outward actions show evidence + get the
   user's final look.
