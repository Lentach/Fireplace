# Latest session summary

**Date:** 2026-07-27 — **no product code changed.** Started as "is master clear?", became an evaluation of the `Egonex-AI/Understand-Anything` plugin (REJECTED), and ended by finding that our own graph ritual was near-random on the Flutter tier. Two commits on `master`: `89aa3a5` + the hook guard. Nothing deployed; live is still **0.0.131 / `f4d3967`**.

## What was done
1. **MEASURED graphify instead of trusting it.** Its `graph.json` file→file import edges score **86.6% precision / 90.7% recall on backend TS** but **0.5% / 1.5% on frontend Dart** — it collapses every relative specifier (`../../theme/rpg_theme.dart`) into one node attributed to an arbitrary file. It claimed the only importer of `contact_network_view.dart` was itself; truth is `contacts_screen.dart:13`. It works on the tier we touch least and is noise on the tier we touch most.
2. **`scripts/impact.mjs` (new)** — "who depends on what I changed, and which tests import it", parsed from source in ~0.6s, no LLM. Handles Dart conditional imports (29 files, multiline, some with two `if` clauses), **bare same-directory specifiers** (the bug that made every `_web`/`_io` file look importer-less), `package:fireplace/…`, TS barrels, untracked files and deletions. **1639 internal specifiers, 0 unresolved.**
3. **Graph rebuild automated + guarded.** `.githooks/post-commit` rebuilds in the background; a changed-extension filter sits **above** the `graphify-hook-start` marker (so `graphify hook install` cannot clobber it) because the graphify block claims "code files only" but actually fires on any commit and re-extracts all 684 files.
4. **`Understand-Anything` rejected** despite genuine first-class Dart support (real `DartExtractor`, vendored tree-sitter WASM, Flutter widget-construction call edges): no MCP/CLI so it cannot run in this harness (its npm `main` points at a file absent from the repo), user-reported tens of millions of tokens per init, and a `curl|bash` + global-symlink + confirmation-suppressing-hook install surface. Two of my initial objections were overstated and withdrawn — an unmerged malicious PR is the normal public-repo threat, and stars:subscribers proves nothing.
5. `CLAUDE.md` §1 L30-31 and §2 L46 rewritten; root-only scratch media gitignored.

## Verification
- **`scripts/impact.selftest.mjs`: 16/16 pass**, hermetic (throwaway repo in `$TMPDIR`), wired into CI before `npm ci`. Run unpiped so the exit code is real.
- Every parser fix checked against `grep` ground truth. Recommended command actually run: **35 passed**.
- Hook fired on `89aa3a5`, rebuild completed (9520 nodes), report advanced to `89aa3a50`. Guard tested both ways on real commits: code → REBUILD, docs → skip.

## Notes for next session
- **`impact.mjs` is an inner-loop hint, NOT a coverage oracle** — static imports only, 3 hops; blind to NestJS DI wiring, §7 wire contracts, assets/config. Full tier suites still gate commits and PRs. Do not let it justify skipping `flutter test` / `npm test`.
- **TRAP: `core.filemode=false` here** — new hooks stage as `100644` even after `chmod +x` and are silently ignored on Linux/fresh clones. Fixed via `git update-index --chmod=+x`; check `git ls-files --stage .githooks/` after adding any hook. Activation is still per-clone: `git config core.hooksPath .githooks`.
- Never answer a Flutter dependency question from `GRAPH_REPORT.md`. Re-run the measurement before trusting graphify's Dart edges again.
- **Dependabot #95 is VALID and still open — do NOT dismiss it.** `207bc06` upgraded only the four `^5.0.5` copies to `5.0.8`; the alert's range is `<= 5.0.7`, which also covers **root `brace-expansion@1.1.16`** and three nested `2.1.2` copies (`@jest/reporters`, `jest-config`, `jest-runtime`) that were never touched. So the lockfile is PARTIALLY upgraded, not fixed. All eight copies are `dev: true` (eslint/jest tooling; the prod container ships prod deps only), so it is not deploy-blocking — but the fix is to upgrade the remaining four, not to close the alert. Earlier notes claiming "#95 fixed in 207bc06" are wrong.
- ➡ Full detail: **`2026-07-27-session-workflow-tooling.md`**.

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
- ➡ Detail: `2026-07-25-session-console-glyphs.md` and `2026-07-25-session-settings-console.md`. **Both 2026-07-25 handoffs are banner-marked SUPERSEDED — do not pick them up** (`2026-07-25-HANDOFF-START-HERE.md`, `2026-07-25-handoff-branch-ready-to-merge.md`); the later brief is `2026-07-26-HANDOFF-START-HERE.md`, itself now historical since PR #98 merged.

---
### Prior latest ↓

**Date:** 2026-07-24 — Removed the top-of-screen "Update available — fully close and reopen the app." nudge on user request (annoying); shipped straight to `master` as frontend **0.0.128**.

## What was done
1. `frontend/lib/screens/main_shell.dart`: deleted the stale-bundle nudge (`_staleNudgeShown` flag + comment, the `kIsWeb` `initState` post-frame `_nudgeIfBundleStale` hook, the method, and the `services/update_check.dart` import). Kept `showTopSnackBar` (still used by the friend-accepted toast).
2. Deleted the now-orphaned service: `services/update_check.dart` + `_stub` + `_web` (only the nudge called `isServedBundleNewer`).
3. Removed the unused `updateAvailableCloseReopen` key from `app_en.arb`/`app_pl.arb`; `flutter gen-l10n` regenerated the getters out of `app_localizations*.dart`.
4. Removed the resolved banner row from `docs/ISSUE-BOARD.md`. Bumped `pubspec.yaml` 0.0.127 → 0.0.128. `graphify update .`.

## Verification
- `flutter analyze lib/screens/main_shell.dart lib/l10n` → No issues found. `git grep` for the key/service/symbol across `frontend/lib` → no matches. Graph: 9218 nodes. Production post-deploy smoke pending below.

## Notes for next session
- Reverts PR #96's stale-bundle nudge only; the underlying stale-PWA reality is unchanged — users still must fully close + reopen after a deploy to activate a new service worker. Never uninstall / clear site data (wipes E2E keys).
- Full: `2026-07-24-remove-stale-bundle-nudge.md`.

---
### Prior latest ↓

**Date:** 2026-07-24 — PWA logout incident root-caused AND hardening released: PR #96 merged, **0.0.127 / `3861166` deployed to production (frontend + backend), smoke passed**. Server auth was CONFIRMED healthy (112/112 refreshes 201 over 14 days); the owner-verified victim suffered a FULL device-side origin-storage wipe (proven via Postgres xmin — tokens AND Signal identity destroyed and regenerated; permanent history loss on that device).

## What was done
1. Ruled out server causes with live VM evidence: `/auth/refresh` deployed + 100% successful; most users hold healthy 365-day sliding sessions; no `[auth-session-end]` warns; secret rotation/clock/CORS refuted.
2. "Logged out after 1 day+" = 24h access-JWT TTL on devices that never call refresh. DB fingerprint: victims' rows never slide (`expires_at` = `created_at`+365d exactly). Top churner was owner's incognito build checks (noise).
3. Verified logout path is E2E-key-safe at source: only `jwt_token`/`refresh_token` removed; re-login reuses on-device Signal store.

## Verification
- Investigation: read-only file:line reads + nginx/docker/psql queries on the VM. Fix branch: backend 536 passed/47 suites; frontend analyze 0 issues, 783 passed/4 skips; targeted regressions for the boot slide (valid-access boot slides once with `X-App-Commit`; slide 401/500 NEVER logs out).

## Notes for next session
- **PR #96 (`fix/pwa-logout`, 0.0.127) is MERGED and DEPLOYED** (backend `deploy-backend.sh` healthy; `deploy-web.ps1` published; post-deploy smoke 5/5; version.json BOM-free with injected `gitCommit`; CORS preflight allows `x-app-commit`). Contents: `navigator.storage.persist()` at every web boot (+`STORAGE_NOT_PERSISTENT` diag), backend `[identity-churn]` WARN on identityPublicKey change, proactive boot session slide, `X-App-Commit` on auth calls, session-end reason + compiled commit on the auth screen, stale-bundle nudge. Backend test count in root CLAUDE.md §3 is 536.
- Devices still on old bundles benefit only after one full close+reopen (the nudge code isn't in their cached bundle). Remind users; never uninstall/clear site data.
- On the next logout report, BEFORE re-deriving anything: (1) grep backend logs for `[identity-churn]` and `[auth-session-end]`; (2) nginx: did the victim's login carry `X-App-Commit`? absent/old = stale bundle; (3) victim's login-screen footer screenshot now shows commit + reason; (4) `refresh_tokens.expires_at` vs `created_at`+365d = never-slid fingerprint. Forensic trap: OTP upsert preserves `createdAt` and overwrites `identityPublicKey` — use Postgres `xmin` for rewrite dating.
- Platform truth (sources verified): `persist()` is real eviction protection on Android/Chrome installed PWAs; on iOS the home-screen install itself is the main exemption and `persist()` is best-effort. Manual site-data wipes are indefensible on any web platform (= Signal Web) — native builds are the only escape.
- NEVER clear site data / rotate JWT_SECRET as a "fix". Full details: `2026-07-24-session.md` (local-only, gitignored by incident rule).

