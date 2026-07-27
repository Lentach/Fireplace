# Latest session summary

**Date:** 2026-07-27 — a workflow/infra session that ended up fixing **two disaster-recovery bugs in production code** (`backend/src/database/migration-runner.ts`), both surfaced by the new cross-tier CI job on its first run. 15 commits, `05e0962..ddbf834`. Nothing deployed; live is still **0.0.131 / `f4d3967`**.

## What was done
1. **MEASURED graphify instead of trusting it.** Its file→file import edges score **86.6%/90.7% on backend TS** but **0.5%/1.5% on frontend Dart** — it collapses every relative specifier into one node attributed to an arbitrary file. It claimed `contact_network_view.dart`'s only importer was itself; truth is `contacts_screen.dart:13`. Kept and automated, but DEMOTED: never answer a Flutter dependency question from `GRAPH_REPORT.md`.
2. **`scripts/impact.mjs` (new)** — who depends on what I changed + which tests import it, parsed from source in ~0.6s. Handles Dart conditional imports, bare same-directory specifiers, `package:fireplace/…`, TS barrels, untracked files, deletions. **1639 specifiers, 0 unresolved.** 16 hermetic self-tests in CI.
3. **`.githooks/post-commit` rebuilds the graph** in the background, guarded to code-only commits (the graphify block claims "code files only" and does not filter).
4. **BUG: `0001_baseline.sql` could never run on a fresh database.** `pg_dump` brackets its dump with `\restrict`/`\unrestrict` psql meta-commands; node-postgres answers `syntax error at or near "\"`. **BUG 2, right behind it:** the baseline ends with `set_config('search_path','',false)`, so the runner's own unqualified tracking INSERT died with `relation "schema_migrations" does not exist`. Both hit only EMPTY databases — i.e. disaster recovery — because prod stamps the baseline instead of running it. Fixed in the runner (baseline is immutable), 3 regression tests.
5. **`e2e-wire` CI job added** — full-stack harness vs real Postgres+backend. It found both bugs on its first run. **11 wire tests green.**
6. **Repo is PRIVATE** (`gh repo view --json isPrivate` → true); docs said "public". All 225 dated summaries are now committed, and the false policy they carried is corrected.
7. Frontend test-count verifier added; `CLAUDE.md` §4–§6 deploy detail moved to the runbook.

## Verification
- Backend **541/47 green**, Flutter **903 + 4 skipped green**, both counts now machine-verified in CI. `e2e-wire` **11 passed** against real Postgres.
- Migration fix falsified by reverting it (test goes red). Every parser fix checked against `grep`.

## Notes for next session
- **`impact.mjs` is an inner-loop hint, NOT a coverage oracle** — static imports, 3 hops; blind to NestJS DI, §7 wire contracts, assets. Full tier suites are **required by project policy** before commits/PRs; nothing enforces that mechanically.
- **`e2e-wire` is now CI-failing** (`continue-on-error` removed after 5 consecutive greens; it caught two DR bugs on its first two runs). **But red is NOT a gate here** — branch protection is a paid feature, 403 on this private free-plan repo, so nothing blocks a push or merge and small fixes still go straight to `master`. Checking the run is a human/agent duty: `gh run list --branch master --limit 1`. If it flakes, restore `continue-on-error: true` deliberately and record it.
- **ROTATE `CONTACT_INBOX_KEY` — a live 64-hex bearer token is in git.** `2026-07-22-session-inbox-extraction.md:63` pastes it into a real URL (`/contact/inbox?key=…`). **PRE-EXISTING, not from this session** — blob `bd5fe89` is byte-identical at `05e0962` and HEAD, introduced by `2a70e38`, and it is in NONE of the 112 newly published summaries (all verified). Found by an independent security review. Rotate it on the VM + `~/fireplace/.env`; history scrub optional since the repo is private. **`gitleaks` is NOT installed**, so the pre-commit fallback is a prefix-only regex that cannot catch a bare high-entropy `?key=` — install gitleaks, and never trust that hook as a reason a paste is safe.
- **TRAP: `core.filemode=false` here** — new hooks stage `100644` even after `chmod +x` and are silently ignored on Linux. Use `git update-index --chmod=+x`; check `git ls-files --stage .githooks/`. Hook activation is per-clone: `git config core.hooksPath .githooks`.
- **Dependabot #95 is VALID — do NOT dismiss.** `207bc06` upgraded only the four `^5.0.5` copies; the range `<= 5.0.7` also covers root `brace-expansion@1.1.16` and three nested `2.1.2`. Partially upgraded, dev-only, not deploy-blocking. Fix the remaining four.
- `gitleaks` is NOT installed here, so the pre-commit scan runs a weaker regex fallback.
- ➡ Detail: **`2026-07-27-session-workflow-tooling.md`**; orientation for this directory: **`README.md`**.

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
- **PR #96 (`fix/pwa-logout`, 0.0.127) is MERGED and DEPLOYED** (backend `deploy-backend.sh` healthy; `deploy-web.ps1` published; post-deploy smoke 5/5; version.json BOM-free with injected `gitCommit`; CORS preflight allows `x-app-commit`). Contents: `navigator.storage.persist()` at every web boot (+`STORAGE_NOT_PERSISTENT` diag), backend `[identity-churn]` WARN on identityPublicKey change, proactive boot session slide, `X-App-Commit` on auth calls, session-end reason + compiled commit on the auth screen, stale-bundle nudge. (That entry said the backend count was 536; it is **541** as of 2026-07-27 and now machine-verified in CI.)
- Devices still on old bundles benefit only after one full close+reopen (the nudge code isn't in their cached bundle). Remind users; never uninstall/clear site data.
- On the next logout report, BEFORE re-deriving anything: (1) grep backend logs for `[identity-churn]` and `[auth-session-end]`; (2) nginx: did the victim's login carry `X-App-Commit`? absent/old = stale bundle; (3) victim's login-screen footer screenshot now shows commit + reason; (4) `refresh_tokens.expires_at` vs `created_at`+365d = never-slid fingerprint. Forensic trap: OTP upsert preserves `createdAt` and overwrites `identityPublicKey` — use Postgres `xmin` for rewrite dating.
- Platform truth (sources verified): `persist()` is real eviction protection on Android/Chrome installed PWAs; on iOS the home-screen install itself is the main exemption and `persist()` is best-effort. Manual site-data wipes are indefensible on any web platform (= Signal Web) — native builds are the only escape.
- NEVER clear site data / rotate JWT_SECRET as a "fix". Full details: `2026-07-24-session.md` — tracked since 2026-07-27; the "local-only, gitignored by incident rule" note that used to be here no longer applies.

