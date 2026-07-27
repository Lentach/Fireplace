# Workflow tooling: impact.mjs, graph automation, and what graphify is actually worth

**Date:** 2026-07-27 — a workflow/infra session that ended up fixing **two disaster-recovery
bugs in production code**. Started as "is master clear?", became an evaluation of the
`Egonex-AI/Understand-Anything` plugin, found that our own graph was near-random on the Flutter
tier, and closed the cross-tier test gap — whose very first CI run exposed both bugs.
15 commits on `master`, `05e0962..ddbf834`. **Product code DID change**:
`backend/src/database/migration-runner.ts`. Nothing deployed; live remains 0.0.131 / `f4d3967`.

## What was done

1. **Evaluated `Egonex-AI/Understand-Anything` (76.4k stars, MIT) — REJECTED, with one surprise
   in its favour.** Read its source, not its README. Dart/Flutter support is genuine and
   first-class: a 737-line `DartExtractor`, a vendored `tree-sitter-dart` WASM grammar, and a call
   graph that models Flutter widget construction (`const Foo()` emits a call edge,
   `dart-extractor.ts:592-613`, with a passing test). Rejected anyway on four grounds:
   - **It cannot run in this harness.** No MCP server, no CLI. It is `SKILL.md` prompts plus
     `agents/*.md` subagent prompts. `package.json main` points at
     `.opencode/plugins/understand-anything.js`, which **does not exist in the repo**. Nothing
     produces the graph without an LLM agent executing SKILL.md.
   - **Cost.** Maintainers deliberately do not measure it (`docs/benchmarks/large-monorepo.md`:
     "does not… count tokens, estimate cost"). Users report a fresh init burning tens of millions
     of tokens (issue #472); file-analyzer is ~80% of spend (PR #176).
   - **Install surface.** `curl | bash` from `main`, clone into `$HOME`, symlinks into every AI
     agent's skill dir, and a git hook instructing the model "Do not ask the user for
     confirmation — just do it" (`hooks/hooks.json`).
   - **It duplicates a tool we already had.**
   *Two claims were walked back during review as overstated: an unmerged obfuscated-payload PR
   (#206/#432) is the normal public-repo contribution threat, NOT evidence that released code was
   compromised; and a 76k-stars/240-subscribers ratio is a curiosity, not proof of anything.*

2. **MEASURED graphify's accuracy instead of assuming it. This is the session's real finding.**
   Compared `graphify-out/graph.json` file→file import edges against imports resolved from source:

   | Tier | Precision | Recall |
   |---|---|---|
   | `backend/src` TypeScript | 86.6% (362/418) | 90.7% (362/399) |
   | `frontend/lib` Dart | **0.5% (7/1458)** | **1.5% (7/463)** |

   Cause: graphify creates one node per import *label*, so every relative specifier
   (`../../theme/rpg_theme.dart`) collapses into a single node attributed to whichever file
   happened to mention it first. Concretely, it reported that the only importer of
   `contact_network_view.dart` was itself; ground truth is `contacts_screen.dart:13`.
   **It works on the tier we touch least and is noise on the tier we touch most.**

3. **Built `scripts/impact.mjs`** — "who depends on what I changed, and which tests import it",
   parsed from source. Deterministic, no LLM, no graph file, ~0.6s. Handles the forms that
   actually appear here: Dart conditional imports (29 files, several multiline, some with two
   `if` clauses), **bare same-directory specifiers** (`import 'bridge_web.dart';` — the bug that
   made every `_web`/`_io` implementation look importer-less), `package:fireplace/…` from the test
   tree, TS extensionless relatives and `index.ts` barrels, untracked new files, and deletions.
   Audited: **1639 internal specifiers, 0 unresolved.**

4. **Automated the graph rebuild.** `graphify hook install` writes `.githooks/post-commit` and
   `post-checkout` (it correctly respects `core.hooksPath`, verified in `hooks.py:152-167`).
   Rebuild is detached and skips rebase/merge states.

5. **Guarded the hook.** The graphify block's comment claims "code files only" but it fires on any
   nonempty commit and then re-extracts all 684 files — a `docs(session)` commit triggered a full
   rebuild. Added a changed-extension filter **above** the `graphify-hook-start` marker so
   `graphify hook install` cannot clobber it on reinstall.

6. **Corrected `CLAUDE.md`.** §1 line 30 (the manual `graphify update .` mandate) is replaced by
   the impact tool plus a note that the hook automates the rebuild; §2 line 45 no longer sends
   agents to `GRAPH_REPORT.md` for dependency answers and records the measured Dart/TS accuracy
   split. Root-level scratch media (`*.jpg`/`*.png`/`*.mp4`) is now gitignored — root only, so
   `frontend/assets/` stays tracked.

### Second round — context budget and dead docs

7. **LATEST.md trimmed 6546 → ~1800 words (~8.7k → ~2.4k tokens).** `AGENTS.md` step 3 makes every
   agent AND every subagent read it at startup, so this was the largest single cost in the
   workflow — larger than anything graph-related. One 2026-07-25 entry was 4756 tokens by itself.
8. **The existing cap measured the wrong thing.** `.githooks/pre-commit` Gate 2 counted ENTRIES,
   so five fat entries passed while six thin ones would be blocked. It now enforces ≤5 entries,
   ≤2600 words total, and ≤700 words per single entry. Proven by staging an over-budget file and
   watching the commit get rejected on both the total and per-entry rules.
9. **DISCOVERY: NEW dated session summaries are not tracked — but the legacy archive is.**
   `.gitignore:51` ignores `.cursor/session-summaries/*` except `LATEST.md`. Exact boundary,
   measured: the **114 dated files up to 2026-07-22** predate the rule and remain TRACKED, so any
   fresh clone can still read them. **Everything from 2026-07-23 onward is local-only** — which
   is every dated file `LATEST` currently links to, **this file included.** `git add` on the
   directory silently skips them, so my earlier "docs(session)" commits contained only
   `LATEST.md` even though I reported the summary as committed. The ignore rule itself is right
   (public repo; these carry VM/infra and incident detail). What it falsifies is the old
   justification for compressing LATEST — off this machine, for anything recent, "the dated file
   has it" is not true. First stated too strongly as "LATEST is the ONLY committed record",
   which the 114 tracked files disprove; `CLAUDE.md` §1 now carries the precise version.
10. **Deleted three banner-marked-SUPERSEDED handoffs** (`2026-07-24-handoff-contact-network-merge`,
   `2026-07-25-HANDOFF-START-HERE`, `2026-07-25-handoff-branch-ready-to-merge`) and the stale
   `.planning/.active_plan`, which still pointed at `2026-07-23-e2e-self-repair` — a plan whose
   own `progress.md` ends "All four investigation phases complete." Every inbound reference was
   repaired. `2026-07-11-...-handoff.md` was a false positive (it says "this file *supersedes*")
   and was KEPT.
11. **Two proposals I withdrew after checking**, rather than manufacturing work: `docs/adr/` is
   absent BY DESIGN (`docs/agents/domain.md:10` — "If any of these files don't exist, proceed
   silently"), and `CLAUDE.md`'s planning-files rule was correct — `task_plan.md`/`findings.md`/
   `progress.md` do exist, inside `.planning/<task>/`. Both became one-line clarifications.
12. **Added one rule: re-verify VOLATILE claims, never inherit them** (git/deploy state, versions,
   CI and alert status, counts, artifact freshness). Narrowed after review so stable facts —
   architecture, wire contracts, documented traps — stay trustworthy as written; an absolutist
   version would have been more ritual than the session removed.

### Third round — the E2E gap, and the two DR bugs it found

13. **`e2e-wire` CI job added** (`.github/workflows/ci.yml`). Full-stack harness: real Postgres
    + backend via `docker compose`, then `flutter test test_e2e`. It is the ONLY automated
    guard on the §7 wire contracts — unit tests on each side mock the other, and `impact.mjs`
    cannot see across the wire. `continue-on-error: true` and `timeout-minutes: 25` are
    STAGING ONLY, to gather reliability signal; while set, **this job is observability, not
    protection.** Promote it to a required check once it has a green streak. Teardown uses
    `docker compose down` without `-v` deliberately, so the repo never normalises a flag
    `CLAUDE.md` §4 bans on prod.
14. **BUG 1 — `0001_baseline.sql` could NEVER execute on a fresh database.** `pg_dump`
    brackets its output with `\restrict` / `\unrestrict`, which are psql META-commands, not
    SQL (our baseline header says pg_dump **16.13** — not a 17+ quirk). Sent through
    node-postgres they raise `syntax error at or near "\"`. Invisible for months because live
    prod and every existing dev DB **stamp** the baseline instead of running it — the only
    paths that execute it are a brand-new environment and **disaster recovery**.
15. **BUG 2, immediately behind it — the tracking INSERT died too.** The baseline ends with
    `set_config('search_path','',false)`, which is session-wide and therefore still in force
    for the `INSERT INTO schema_migrations` that runs right after it *inside the same
    transaction*: `relation "schema_migrations" does not exist`. The `RESET ALL` that repairs
    the session only runs after COMMIT. All four references are now `public.`-qualified,
    matching the rule `backend/CLAUDE.md` §4 already stated for migration SQL.
16. **Both fixes live in the runner, not the migration** — applied migration files are
    IMMUTABLE (`backend/CLAUDE.md` §4), and a later migration cannot repair a baseline that
    never starts. The meta-command strip is scoped to `BASELINE_FILENAME` alone: the regex is
    line-based and would corrupt a dollar-quoted body, so every other migration is executed
    byte-for-byte, with a test pinning that.
17. **Repo is PRIVATE** — `gh repo view --json isPrivate` → `true`, while `CLAUDE.md:20` and
    `.gitignore` both asserted "public" and had shaped the whole summary-visibility policy.
    Un-ignored `.cursor/session-summaries/*`: 111 previously-local files committed, 225 total.
    Scanned for secrets/PII first (clean). Then scrubbed the now-published false guidance —
    correction banner on `2026-07-26-HANDOFF-START-HERE.md`, and a new `README.md` in the
    directory carrying both corrections once instead of editing 20 historical files.
18. **Frontend test-count verifier** (`scripts/verify-claude-frontend-test-counts.mjs`),
    mirroring the backend one. `LATEST` claimed 879; the real number was 903 — already
    drifted. It initially FAILED on CI: `flutter test` prints `🎉 903 tests passed, 4 skipped.`
    when not attached to a TTY, not the `+N ~M:` progress counter a local run emits. Parser
    now handles both. The CI step redirects to a log instead of `| tee`, so its exit status is
    Flutter's own and does not depend on pipefail.
19. **`CLAUDE.md` §4–§6 compressed**, deploy-only detail moved into
    `.cursor/rules/production-vm-deploy.mdc` (loaded on demand). Checked FIRST that the runbook
    did not already cover it — it did not cover the smoke script, staging, backup cron, or the
    env table, so those were MOVED, not deleted. Verified afterwards that every relocated term
    resolves in one file or the other. Net 3341 → 3120 tokens despite six rules added.

## Key files

- `scripts/impact.mjs` (new) — the tool. Header documents its scope limit.
- `scripts/impact.selftest.mjs` (new) — 16 hermetic cases in a throwaway git repo in `$TMPDIR`;
  never touches the working copy. Wired into CI's backend job **before** `npm ci` so a broken tool
  fails fast.
- `.githooks/post-commit`, `.githooks/post-checkout` (new) — staged `100755`; see the trap below.
- `CLAUDE.md` §1 (impact tool, hook automation, LATEST size cap, the tracked-vs-local truth,
  volatile-claim rule, planning-files clarification) and §2 (graph accuracy split), §9 (ADR
  laziness). `.github/workflows/ci.yml` — self-test step. `.gitignore` — root-only scratch media.
- `.githooks/pre-commit` — Gate 2 rewritten from entry-count to a three-part size budget.
- `.cursor/session-summaries/LATEST.md` — trimmed. (It was the only committed session file at
  the time; since item 17 all 225 dated summaries are tracked too.)
- DELETED: three superseded `*handoff*` files + `.planning/.active_plan`.

## Verification

- **Self-test: 16/16 pass**, run unpiped so the exit code is genuinely the test's.
- Every parser fix was verified against `grep` ground truth before and after:
  `contact_network_view.dart` → `contacts_screen.dart`; `badging_bridge_web.dart` → three
  importers including two conditional; `notification_cleaner_io.dart` → the two files whose
  second `if` clause names it.
- Recommended test command actually executed: `flutter test test/widgets/contact_network_view_test.dart
  test/screens/contacts_screen_search_test.dart` → **35 passed**.
- Size gate proven by staging an over-budget LATEST: rejected on both `is 3414 words (cap 2600)`
  and `single entry of 2204 words (cap 700)`, then restored.
- CI run `30284101070` on `b4f2995`: both jobs SUCCESS, including `Self-test scripts/impact.mjs`
  running before `Install backend dependencies` — proves the step works on Linux and that
  `working-directory: .` overrides the job's `backend` default.
- Every inbound reference to a deleted file was grepped and repaired (`2026-07-26-HANDOFF-START-HERE.md`,
  `2026-07-26-session-release-0.0.129.md`, `LATEST.md`); a final grep returns nothing dangling.
- Hook fired on `89aa3a5`; background rebuild completed (9520 nodes, 13579 edges) and the report's
  `Built from commit` advanced to `89aa3a50`.
- Guard tested both directions against real history: `89aa3a5` and `c0fcae1` → REBUILD;
  `05e0962` (docs) and the guard commit itself → skip.
- **Product code WAS touched** (`backend/src/database/migration-runner.ts`) — see items 14-16.
  Full suites re-run and green: backend **541 tests / 47 suites**, Flutter **903 passed / 4
  skipped**, `e2e-wire` **11 wire tests** against real Postgres. Both counts are now pinned in
  `CLAUDE.md` §3 and machine-verified in CI. Final green run: **`30293387936`** on `ddbf834`,
  all three jobs SUCCESS (`backend`, `frontend`, `e2e-wire`).

## Notes for next session

- **`impact.mjs` is an inner-loop hint, NOT a coverage oracle.** It follows static imports for
  `--depth` hops (default 3). It cannot see NestJS DI/module wiring, the §7 wire contracts,
  assets/config, or anything a test exercises without importing the changed file. The full tier
  suite still gates commits and PRs — this is stated in the script header, in its output
  ("Retest (inner loop only…)"), and in `CLAUDE.md`. Do not let it become an excuse to skip
  `flutter test` / `npm test`.
- **TRAP — `core.filemode=false` on this machine.** New hooks staged as `100644` even after
  `chmod +x`; they would be silently ignored on Linux or a fresh clone. Fixed with
  `git update-index --chmod=+x`. Check `git ls-files --stage .githooks/` after adding any hook.
- **Hook activation is still per-clone:** `git config core.hooksPath .githooks`, same one-time
  step the secret-scanning pre-commit hook already needed.
- **graphify is now automated but demoted.** Keep using it for backend structure and symbol
  inventory; never answer a Flutter dependency question from `GRAPH_REPORT.md`. Its ~508
  `[[_COMMUNITY_*]]` wikilinks point at a `wiki/` dir that does not exist, and its
  "Surprising Connections" section contains provably wrong edges. If it ever fixes Dart relative
  specifiers, re-run the measurement before trusting it again.
- If `impact.mjs` grows a parsing rule, add a case to `impact.selftest.mjs` in the same commit —
  that is the whole point of it existing.
- **Dependabot #95 is VALID and still open. Do NOT dismiss it, and do NOT re-fix the four
  already-patched copies.** The alert's vulnerable range is `<= 5.0.7` — which covers 1.x and
  2.x as well, not merely 5.x below the patch. `207bc06` upgraded only the four `^5.0.5` entries
  to `5.0.8`; still in range and untouched are **root `brace-expansion@1.1.16`** and three
  nested `2.1.2` copies (`@jest/reporters`, `jest-config`, `jest-runtime`). The lockfile is
  therefore PARTIALLY upgraded. All eight copies are `dev: true` — reachable only through
  eslint/jest tooling, and the prod container installs prod deps only — so it is not
  deploy-blocking. The real fix is upgrading those remaining four (npm's resolver can rewrite
  neighbouring entries, so diff the lock and run the backend suite). Any earlier note saying
  "#95 fixed in `207bc06`" is wrong; this bullet supersedes it.
