# Latest session summary

**Date:** 2026-07-28 — **RELEASED 0.0.133 / `b6fa385`, frontend only, smoke 5/5.** Five-bug batch: PR **#103** `fix/composer-and-preview-quickwins` (bugs 2/4/5) and PR **#104** `fix/avatar-count-and-ping` (bugs 1/3/3e), both merged with owner approval after independent review + hardening. Backend untouched — `/version` stays `0.0.132/05fc423` BY DESIGN. Worktrees removed after merge.

- **Bug 2 restored the composer emoji button** — removed deliberately in `6131b15` (0.0.115) as a "keyboard duplicate"; premise wrong, owner ruled restore. Full pin contract back (`composerBottomPanelPinned` + viewport bottom-pin); `frontend/CLAUDE.md` §7 ban line superseded. **iOS-style emotes declined: Apple Color Emoji is not redistributable**; iOS already renders Apple glyphs via fallback.
- **Bug 4:** mobile (defaultTargetPlatform android/iOS, incl. phone PWA) action key now inserts newline (`TextInputAction.newline`, no onSubmitted); desktop byte-identical (Enter=newline, Ctrl/Cmd+Enter=send — owner ruled keep).
- **Bug 5:** Anti-Quantum Note previews show the l10n label on every surface (tile, reply bar, pinned banner, in-bubble quote via `reply_preview_helper`). **Link-preview consumption CLEARED** three ways (client excludes+strips, backend skips encrypted, GET /note/:token is a SELECT — burn is POST reveal only). No wire change.
- **Bug 1 root cause:** `_restoreUserFromAccessJwt` clobbered `profilePhotos`/`about` on EVERY silent refresh (even during boot hydrate) → self card "1/3" while others saw 3. Fix: same-account restore `copyWith`s the hydrated user. Swipe-dead gallery was collateral (tap-zone nav gated on photos>1), self-heals.
- **Bug 3 root cause:** ping plaintext '' → lossy persisted-restore kept `[encrypted]` → forced re-decrypt every chat entry → effect re-fired forever. Fix: persisted PING restores as decrypted (consume-once by construction) + transient id dedup. Persisted "played-ids cache" band-aid named and rejected. **Bug 3e** (separate): overlay perf — RepaintBoundary + Fade/ScaleTransition over static child.
- Tests: A **925+4** green, B **911+4** green, fail-before proven by stashing lib per bug. Merged master reconciled to **933** (union suite run confirmed `+933 ~4` before merging #104); master CI green on `b6fa385` before deploy.
- Review round: Branch A zero findings; Branch B P3 + three ping edges all FIXED with fail-before tests (early-unmount latch, unseen-ping resurrection via the durable READ mark, READ gate on the live trigger against silent persist loss).
- **⚠ Owner must device-check the restored composer on the phone** (keyboard→emoji toggle→toggle back→send from panel→system back→mic): widget tests cannot exercise visualViewport/450ms-debounce/black-flash. Rollback if it fights the keyboard: `git revert` the #103 merge or redeploy from `6531aab` (last pre-batch master, 0.0.132) via `deploy-web.ps1`.
- Codex-backed default `task` subagents are usage-walled; `sonic`/`scout` (Anthropic) work — route delegation there.
- **PR #107 `feat/hot-stone-default` OPEN, CI green, NOT merged/deployed:** Hot Stone (the 'light' warm-paper+ember theme, renamed from "Warm Paper"/"Ciepły papier" → "Hot Stone"/"Gorący kamień") is the default for FRESH INSTALLS ONLY (saved prefs win; legacy dark_mode_preference still maps to dark). Login screen now ALWAYS wears Hot Stone (supersedes the 2026-07-18 always-Cosmic front door; render-verified on web). main.dart resolves the saved theme BEFORE runApp (guarded) → no cold-start theme flash either direction. index.html + manifest.json first-paint colors flipped to #F7F4F0; the contract test now parses BOTH files. New token successColorLight. Suite **939+4** green.
- ➡ Detail: **`2026-07-28-session-bugfix-batch.md`**; diagnosis evidence: `.planning/bugfix-batch-2026-07/` (local-only).

---
### Prior latest ↓

**Date:** 2026-07-27 — **agent tooling audit + two credential rotations.** No app source touched. 6 commits, CI green. Live unchanged at **0.0.132 / `05fc423`**.

- **Two live secrets found and killed.** `CONTACT_INBOX_KEY` rotated on the VM (old → **404**, issue **#100 closed**). And a SECOND, previously unknown one: `CONTEXT7_API_KEY` was **tracked and pushed** in `.claude/settings.local.json` (from `fdd3aa2`, an unrelated feature commit) — confirmed live, now revoked and verified **401**. That file is untracked and gitignored by glob.
- **Two enforcement gates that did not exist.** `deploy-web.ps1` now runs the post-deploy smoke and **FAILS the deploy** on a bundle-sha mismatch (falsified both ways against live prod; also catches the exit-21 silent-halt trap). And a **backend lint ratchet** in CI — lint was rotting from 726 → 1320 total errors at ~+30/day because nothing ran it. The ratchet gates a **split count**: **839** real (type-safety) errors strictly, proven platform-identical, plus 481 formatting with ±5 tolerance. It fails only when the number GOES UP.
- **Installed:** `gitleaks` v8.30.1 (**#101 closed**; proven to block a 64-hex `?key=` at entropy 3.97), `osv-scanner` v2.4.0, `trivy` v0.72.0, `dart mcp-server` 1.1.0 (project-scoped `.omp/mcp.json`, **mount unverified — check `/mcp list`**).
- **Prod container scanned for the first time:** 1 CRITICAL + 5 HIGH, **all in npm's bundled tree, none in the app**; `picomatch` in `/app` is already the patched 4.0.4. Container runs `node dist/main.js` and never invokes npm → **not exploitable**. Fix arrives with the next `node:22-alpine` rebuild.
- **Measured, and it killed two ideas:** a `dart format` CI gate is unreachable (reformats **146/368 files**), and a "run only affected tests" runner is **strictly worse** than `flutter test` — cost curve now in `frontend/CLAUDE.md` §1. Also: **`impact.mjs` reports a nonexistent path as "no dependents", exit 0** — a typo reads as "safe". Unfixed.
- ➡ Detail: **`2026-07-27-session-tooling-audit.md`**. Tier list + evidence: `.planning/tooling-audit/` (local-only).

---
### Prior latest ↓

**Date:** 2026-07-27 — **RELEASED 0.0.132 / `05fc423`, both surfaces, smoke 5/5.** A workflow/infra session that ended up fixing **two disaster-recovery bugs in production code** (`backend/src/database/migration-runner.ts`), both surfaced by the new cross-tier CI job on its very first run. 18 commits, `05e0962..05fc423`.

## What was done
1. **MEASURED graphify instead of trusting it.** Its file→file import edges score **86.6%/90.7% on backend TS** but **0.5%/1.5% on frontend Dart** — every relative specifier collapses into one node attributed to an arbitrary file. It claimed `contact_network_view.dart`'s only importer was itself; truth is `contacts_screen.dart:13`. Kept and automated, but DEMOTED: never answer a Flutter dependency question from `GRAPH_REPORT.md`.
2. **`scripts/impact.mjs` (new)** — who depends on what I changed + which tests import it, parsed from source in ~0.6s. Handles Dart conditional imports, bare same-directory specifiers, `package:fireplace/…`, TS barrels, untracked files, deletions. **1639 specifiers, 0 unresolved.** 16 hermetic self-tests in CI.
3. **`.githooks/post-commit` rebuilds the graph** in the background, guarded to code-only commits (the graphify block claims "code files only" and does not filter).
4. **BUG: `0001_baseline.sql` could never run on a fresh database.** `pg_dump` brackets its dump with `\restrict`/`\unrestrict` psql meta-commands; node-postgres answers `syntax error at or near "\"`. **BUG 2, right behind it:** the baseline ends with `set_config('search_path','',false)`, so the runner's own unqualified tracking INSERT died with `relation "schema_migrations" does not exist`. Both hit only EMPTY databases — i.e. disaster recovery — because prod stamps the baseline instead of running it. Fixed in the runner (baseline is immutable), 3 regression tests.
5. **`e2e-wire` CI job added** — full-stack harness vs real Postgres+backend. It found both bugs on its first run. **11 wire tests green.**
6. **Repo is PRIVATE** (`gh repo view --json isPrivate` → true); docs said "public". All 226 dated summaries are committed now, and the false policy they carried is corrected.
7. Frontend test-count verifier added; `CLAUDE.md` §4–§6 moved to the runbook.

## Verification
- Backend **541/47 green**, Flutter **903 + 4 skipped green**, both counts now machine-verified in CI. `e2e-wire` **11 passed** against real Postgres.
- Migration fix falsified by reverting it (test goes red). Every parser fix checked against `grep`.
- **Release 0.0.132**: CI green on `05fc423` (all three jobs) BEFORE deploying. Backend healthy in 10s, `/health` `db:ok` — the runner booted clean on the live DB, confirming the fix misses the stamped-baseline path. **Smoke 5/5**, including `main.dart.js` literally containing `05fc423`.

## Notes for next session
- **`impact.mjs` is an inner-loop hint, NOT a coverage oracle** — static imports, 3 hops; blind to NestJS DI, §7 wire contracts, assets. Full tier suites are **required by project policy** before commits/PRs; nothing enforces that mechanically.
- **`e2e-wire` is now CI-failing** (`continue-on-error` removed after 5 consecutive greens; it caught two DR bugs on its first two runs). **But red is NOT a gate here** — branch protection is a paid feature, 403 on this private free-plan repo, so nothing blocks a push or merge and small fixes still go straight to `master`. Checking the run is a human/agent duty: `gh run list --branch master --limit 1`. If it flakes, restore `continue-on-error: true` deliberately and record it.
- **Owner must fully close + reopen the PWA** to pick up 0.0.132 (Settings footer → `0.0.132 / 05fc423`). **NEVER uninstall or clear site data** — that destroys the local E2E Signal keys.
- **Open work is now tracked as GitHub issues — read them, do not re-derive from here.**
  - **#100 + #101 CLOSED 2026-07-27.** `CONTACT_INBOX_KEY` **rotated** (new → 200, old → **404**; the value at `2026-07-22-session-inbox-extraction.md:63` is **DEAD** — do not re-raise it). `gitleaks` **v8.30.1 installed** in `~/.local/bin`; the hook's gitleaks branch is live and proven to block a 64-hex `?key=` at entropy 3.97.
  - **Also rotated: the `CONTEXT7_API_KEY`** that was tracked in `.claude/settings.local.json` — revoked at context7.com, verified **401**. That file is now untracked and gitignored by glob.
  - **#102: finish Dependabot #95.** Still open. `osv-scanner` confirms **4 of 8** `brace-expansion` copies vulnerable: root `1.1.16` + `2.1.2` under `@jest/reporters`, `jest-config`, `jest-runtime`. Dev-only. **Do not dismiss.**
- ➡ Detail: this session **`2026-07-27-session-tooling-audit.md`** (tooling audit, S-tier installs, both key rotations); earlier that day **`2026-07-27-session-workflow-tooling.md`**; orientation: **`README.md`**.

---
### Prior latest ↓

**Date:** 2026-07-27 — three releases. `feat/nav-rework` → PR #98 → **0.0.130**; `feat/backlog-sweep` → PR #99 (`f4d3967`) → **0.0.131 on BOTH surfaces**, smoke 5/5. First backend production deploy of the run: `deploy-backend.sh` derives `APP_VERSION` from `frontend/pubspec.yaml`, so one bump versioned both. Query-only, **no schema migration**.

- **Ghost invites are LIVE and proven over a real socket** (`getSentRequests` + `sentRequestsList`, refreshed after send/accept/reject). Additive by design: `pendingRequestsCount` and `friendRequestsList` stay INBOUND-only. Needed the backend deploy; without it the client degrades to an empty list.
- **`EventLog.discard` exists because clear-assertions were VACUOUS without it** — `EventLog.next` scans the whole buffer with no cursor, and connecting already buffers an empty `sentRequestsList`, so a "must be empty" wait passed on the CONNECT-time empty. **Any E2E asserting a STATE TRANSITION must `discard` immediately before the action.**
- Chats `+` → glass honeycomb picker; glyph geometry moved onto `ConsoleGlyphGeometry`; `ContactNetworkView` stays provider-free (takes a default-empty `sentInvitees`).
- **PROCEDURE EXCEPTION, recorded honestly:** the 0.0.131 bump was NOT the last branch commit (`280a802` bump → `c0fcae1` test). Deploys key off the MERGE commit and both surfaces report `0.0.131 / f4d3967`, so nothing in prod is inconsistent. **Do not "fix" the history.** Next time hold the bump until verification is done.
- **RE-DEFERRED by the owner: the honeycomb `ListView` rewrite.** Build+layout is still O(N) (`SingleChildScrollView` + one full-height `Stack`; only visual subtrees are windowed). A throwaway probe measured 55.4/66.5/72.0/78.1/**135.5** ms at 20/50/100/200/400 — DIRECTIONAL ONLY, not comparable to the 2026-07-24 table. The cliff bites above ~200 contacts, which is not real yet. Do not record as done.
- ➡ `2026-07-27-session-backlog-sweep.md`, `2026-07-27-session-release-0.0.130.md`, `2026-07-27-session-nav-motion-and-glyphs.md`.

---
### Prior latest ↓

**Date:** 2026-07-25 — `feat/contact-network`: the whole visual pass. Contacts **Honeycomb Core** (header search, long-press → chat, People board with inbound port + add cell), **Chats list redesign** (hex avatars, unread as a lit row edge, live/normal/cold row weights), **Settings "local node console"**, and a rebuilt console glyph set + all three Settings sub-screens. Owner drove every step from renders and from his phone. Ephemeral branch deploy `85a04dc`, still 0.0.128 (branch deploys never bump semver), smoke 5/5.

- **`LocalNodeCore` is shared by Contacts and Settings on purpose** — same widget because it is the same entity (you). It stays a CIRCLE among hexes deliberately; that shape difference marks the local node.
- **Perf traps paid, keep them paid:** route fill REPAINTS, it no longer rebuilds (`AnimatedBuilder` wraps only the `CustomPaint`, not the `Stack` — it was ≈6k subtree builds per tap at N=100). Avatars arm lazily per row via `ValueNotifier` + `ValueListenableBuilder` around each avatar LEAF, never `setState` on the field. The high-water mark resets in `didUpdateWidget` compared **by `id`** (`UserModel` has no `==`).
- **Two things were built, shown, and DELETED at the owner's request — do NOT rebuild:** the "power-on scan" entrance, and the local node BUS (rail down the gutter). Both were rendered, tested and deployed before he rejected them on device.
- **Renders flatter what his hand rejects.** Render to pick a DIRECTION; deploy to get a VERDICT.
- `MainShell`'s `IndexedStack` wraps children in `Visibility(maintainAnimation: true)`, so an offstage tab's animations run at app boot — the honeycomb's entrance stagger has never actually been seen. Status quo, and FINE.
- **NEVER run `dart format lib/`** — it reformatted 70 untouched files. Format only files you edited.
- **Ask before opening the browser tool** — it is not headless and pops a window in front of the owner.
- ➡ Detail: `2026-07-25-session-console-glyphs.md` and `2026-07-25-session-settings-console.md`. The 2026-07-25 handoffs were DELETED on 2026-07-27 (they were banner-marked SUPERSEDED and one nearly got followed); `2026-07-26-HANDOFF-START-HERE.md` survives as historical context only — PR #98 shipped what it gated.
