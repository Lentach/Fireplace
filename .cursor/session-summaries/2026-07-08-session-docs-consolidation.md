# Agent instruction consolidation — CLAUDE.md single source of truth (PR #36)

**Date:** 2026-07-08

## What was done

Cleaned the three-way instruction mess (Claude Code `CLAUDE.md` / Cursor `.cursor/rules` / Codex+OMP `AGENTS.md`). Before: the same facts (deploy, version policy, session summaries, graphify, language rules) lived at 3 compression levels in ~390 lines of overlapping always-loaded instruction, drifting independently. After: every fact lives in exactly one file.

- **`CLAUDE.md` = canonical.** Absorbed the unique content that only lived elsewhere:
  - §1: subagent context rule (subagents don't inherit context — tell them to read the files), full blunt-tone rule, rich commit policy (push-in-same-checkpoint rationale, feature branches don't auto-deploy)
  - §4: pointer to the full deploy runbook, branch-test-before-merge protocol (frontend on PC / backend on VPS), VM log `grep --line-buffered` tip, PWA cache-bust/incognito nuance
  - §5: "bump by +1 = PATCH increment" interpretation rule, Android `versionCode` note
  - tail: backend test-count maintenance rule (verifier)
- **`AGENTS.md`: 183 lines → 22-line universal bootstrap** — read CLAUDE.md + tier file + LATEST.md, ground-rule pointers only. All harnesses (Codex/Cursor/OMP) now land on the same canonical content.
- **Deleted 4 `alwaysApply` rules** duplicated verbatim inside CLAUDE.md: `version-bump.mdc`, `code-in-english.mdc`, `session-summaries.mdc`, `graphify.mdc`. Kept: `On-every-check.mdc` (1-line Cursor loader) and `production-vm-deploy.mdc` (conditional deploy runbook — now explicitly pointed to from CLAUDE.md §4).
- `frontend/pubspec.yaml` version comment redirected from the deleted rule to CLAUDE.md §5 (+ mojibake dash fix).
- Recon confirmed `frontend/CLAUDE.md` already carried all frontend-specific AGENTS.md content (gradle repair, emulator BASE_URL, reactions UX) — nothing migrated there.

## Key files

- `CLAUDE.md` — enriched (§1, §4, §5, tail)
- `AGENTS.md` — rewritten as bootstrap pointer
- `.cursor/rules/{version-bump,code-in-english,session-summaries,graphify}.mdc` — deleted
- `frontend/pubspec.yaml` — comment pointer fix
- Branch `docs/instruction-cleanup`, commits `d461b0e` + `f41c61e` (audit sharpening), **PR #36** (base master) — docs-only, **no version bump** per §5 rule

## Verification

- `node scripts/verify-claude-backend-test-counts.mjs` → OK (407 tests, 42 suites)
- Repo-wide grep for deleted rule filenames → only `pubspec.yaml` referenced one (fixed)
- Diff reviewed: `AGENTS.md -108 lines`, `CLAUDE.md +9 net`, 4 rule files `-78`
- Git incident mid-session: a concurrent `checkout master && pull` moved HEAD, so the commit initially landed on local master and the pushed branch was empty (`gh: No commits between master and branch`). Repaired via `git branch -f docs/instruction-cleanup d461b0e`, reset local master to origin, re-pushed (fast-forward), PR created.
- **Truth audit (same session, follow-up):** 3 parallel read-only auditors (deploy scripts / env+commands / wire contracts) + inline arch pass verified ~60 root-CLAUDE.md claims against source. Result: ZERO hard factual drift. Live prod checked: `/health` ok, `/version` = 0.0.95/283ecb7, `/version.json` = 0.0.95. Sharpened in `f41c61e`: §2 module claim → counted pointer to `backend/CLAUDE.md` §2 (was silently omitting 7 modules); §4 deploy-backend wording → precise `up -d` semantics (backend recreated, db stays up) + bare-`up -d` 0.0.1/unknown footgun.
- **Dead-code deletion (same session, master `3febc63`):** `SocketService.deleteConversation` removed — LSP references = declaration only, zero callers; backend has no `deleteConversation` handler (live path: `ConversationsProvider.deleteConversation` → WS `deleteConversationOnly`). `flutter analyze` clean, graphify updated. No version bump (zero behavior change); rides the next frontend deploy.

## Follow-up (same session, evening): housekeeping + security + smoke tooling

- **Branch cleanup:** removed worktree `.worktrees/fix-sticky-sessions` (only stale LATEST.md scratch inside) + empty `.worktrees/`; deleted `fix/emote-message-layout` (996943f, patch-equivalent in master, PR #28), `fix/sticky-sessions` (70d2761, patch-equivalent, PR #27), `fix/note-preview-label` (bd17a4e, superseded by PR #30 banner — user-ordered). Deleted stray `%TEMP%pre30_send.dart`. KEPT: `audit/full-review` (local-only security backlog — STILL NEEDS OFF-DISK BACKUP) and `codex/ios-composer-textarea-guard` (prototype).
- **Dependabot (`7a2cb65`):** `.github/dependabot.yml` — monthly grouped version PRs for backend npm / frontend pub / actions, caps 3/3/2. Security alerts+updates need repo Settings toggles (user-side).
- **Post-deploy smoke (`cda69c1` + docs `ff3ca15`):** `scripts/smoke/post-deploy-smoke.mjs` — /health, /version.json, /version, bundle-commit stale-build detector (served `main.dart.js` must contain the expected short-sha; the GIT_COMMIT dart-define is a findable literal, single bundle, no part files), Playwright fresh-profile boot probe (pageerrors = warn only). Live-verified BOTH paths: default run correctly FAILS on today's stale frontend (prod serves 0.0.95/`283ecb7`, master ahead); `--commit 283ecb7` full-passes. Referenced in CLAUDE.md §4.
- **Live prod state at session end:** backend 0.0.96/`080d660` (current), frontend 0.0.95/`283ecb7` (STALE — a `deploy-web.ps1` run is owed to ship 0.0.96 frontend incl. the dead-code removal).

## Notes for next session

- ~~Frontend deploy owed~~ **CLOSED:** user deployed; smoke FULL PASS against HEAD `ff3ca15` — frontend 0.0.96 live, bundle-commit exact, backend 0.0.96/`080d660`, app boots. Dead-code removal + all docs live in prod.
- **User-side toggles owed:** GitHub Settings → Code security: enable Dependabot alerts + security updates + secret scanning (+ push protection); uptime monitor for `/health` + backup-cron ping still unconfigured.
- ~~`audit/full-review` backup owed~~ **CLOSED:** user ordered deletion instead (was `e2e186a`; reflog-recoverable ~30 days). User also removed `codex/ios-composer-textarea-guard`; local branches now = `master` only.
- Earlier same day: OMP harness tooling cleanup (MCP dedup, node_repl disable, Dart+TS LSP wiring) — see `2026-07-08-session-agent-tooling.md`. MCP changes take effect next OMP session; verify with `/mcp list` (expect single context7, no node_repl).
