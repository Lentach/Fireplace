# CLAUDE.md size reduction

**Date:** 2026-06-01

## What was done
Reduced `CLAUDE.md` from 440 lines / ~41KB to 284 lines / ~35.8KB (−35% lines, −12% bytes) using the `claude-md-management:claude-md-improver` skill at the **moderate** aggressiveness level chosen by the user. Goal: trim redundancy + content that duplicates code/git history while preserving every non-obvious gotcha.

Changes (gotchas untouched):
- **§4 Database Schema:** replaced the ~113-line mermaid `erDiagram` (a near-verbatim copy of `*.entity.ts`) with a compact summary keeping only the non-obvious facts — relations, `eager` flags, enum values, nullable/non-obvious columns, and constraints (unique keys, CASCADE FKs).
- **§3 File Location Map:** replaced the two large file-enumeration tables (~60 files) with directory-level pointers, keeping the non-obvious bits: conditional-import stub/io/web pairs, re-export shims (do-not-delete), Signal stores, service worker.
- **§2 Architecture Overview:** replaced the mermaid flowchart with a one-line topology description; kept the high-value provider/service/wiring prose.
- **§1 iOS WebKit keyboard inset bullet:** tightened — dropped the on-device measurement narrative + removed-feature notes; kept the gotcha, the fix, and the dev-tool overlay pointer.

Left intact: all of §1 substance (incl. the dense decrypt-ordering exception list and focus-guard bullet), §5 how-tos, §6 runtime behaviors, §7 widget gotchas, §8 env vars, §9 limitations, Rules header.

## Key files
- `CLAUDE.md` (§2, §3, §4 collapsed; one §1 bullet tightened)

## Verification
- `wc -l CLAUDE.md` → 284 (was 440); `wc -c CLAUDE.md` → 35775 (was 40859)
- Re-read edited region (lines 122–183): sections flow coherently, no dangling references.
- No code changed → no test run required.

## Notes for next session
- The remaining byte weight is concentrated in the §1 gotcha paragraphs, which are intentionally preserved. Further reduction would require sacrificing hard-won gotchas — not advised without explicit direction.
- `.worktrees/composer-overhaul/CLAUDE.md` is a separate worktree copy and was NOT touched.
