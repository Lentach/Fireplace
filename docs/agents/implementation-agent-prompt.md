# Implementation-agent prompt

## Source-backed findings

- **Be specific and direct.** OpenAI says GPT-4.1 follows instructions literally and benefits from clear, specific instructions; Anthropic recommends naming the exact file, scenario, constraints, and relevant existing pattern. [OpenAI](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide) · [Anthropic](https://code.claude.com/docs/en/best-practices#provide-specific-context-in-your-prompts)
- **Separate investigation from implementation.** OpenAI's coding-agent workflow calls for exploring relevant files, searching related symbols, and reading the target section before editing. Anthropic recommends explore → plan → implement to avoid solving the wrong problem. [OpenAI](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide) · [Anthropic](https://code.claude.com/docs/en/best-practices#explore-first-then-plan-then-code)
- **Constrain scope explicitly.** Anthropic recommends scoping the task and provides a “do not extend beyond…” pattern for agents; precise context reduces corrective turns. [Anthropic](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#let-claude-take-the-wheel)
- **Give a check and require evidence.** Anthropic recommends a runnable pass/fail check and asks agents to show the command result or other evidence, not merely assert success. [Anthropic](https://code.claude.com/docs/en/best-practices#give-claude-a-way-to-verify-its-work)
- **Keep durable instructions concise.** Anthropic says bloated instruction files cause actual instructions to be ignored; retain only rules whose removal would cause mistakes. [Anthropic](https://code.claude.com/docs/en/best-practices#write-an-effective-claudemd)

## Proposed fresh-agent template

```text
Role: You are the implementation owner for <feature/bug>. Deliver the approved design faithfully; do not redesign product behavior.

Task: <observable user outcome and affected area>.
Context: Read <required project instructions>, <approved design/spec>, and inspect <known files/patterns>. Search for adjacent callers before editing; do not guess file contents.

Scope: Change <in-scope behavior/files>. Do not change <explicit non-goals>. Reuse existing conventions and dependencies.

Design gate: First inspect the code and present a concrete design: affected files, data/state flow, UI/behavior details, edge cases, and focused verification. STOP and wait for explicit approval. Make no implementation edits before approval.

After approval: Implement only the approved design, migrate every affected caller, and remove superseded code. If discovery invalidates the approved design, stop and report the conflict rather than improvising scope.

Acceptance: <numbered observable outcomes>. Run <focused command/manual scenario>; fix failures. Report changed files and the exact verification evidence.
```

## Five concrete improvements

1. Replace “build the user card” with the target outcome and named UI/data boundaries.
2. Name mandatory context files and require source inspection before edits.
3. List explicit non-goals to prevent feature creep.
4. Add the design gate: concrete proposal first, then wait for explicit approval before writes.
5. Define focused acceptance checks and require their observed output as completion evidence.
