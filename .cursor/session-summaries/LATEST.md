# Latest session summary

**Date:** 2026-07-24 — Contacts tab = the **Honeycomb Core** on `feat/contact-network`, now with search living IN the header capsule (owner: "i would go with option 2 lets see serchbar in the header"). Still an ephemeral branch deploy, NOT merged, no version bump.

## What was done
1. Honeycomb Core (2026-07-23, owner verdict "all is perfect"): `ContactNetworkView` rewritten around the pure `ContactHexLayout` — reticle core top-center with the user's avatar, fixed-width staggered hex field below (4-3 rows on phones, up to 8-7 on desktop, partial last row self-centers), alphabetical order = spatial order, vertical scroll only. Contact avatar fills each hex. Socket stub per hex: **one pin = no conversation, two pins = active chat — owner explicitly KEPT this, do not unify.** Tap fills the route from the hex up to the core (480ms easeInOut + head dot) and opens the card; the strip NEVER appears on bare keyboard focus (focus = halo, Enter activates). Deleted: elliptical-ring engine, drag-to-pin store, Reset button, InteractiveViewer, dogleg traces, identicons.
2. Search moved into the header (2026-07-24): the 54px band under the header is GONE. Closed state = bare magnifier LEFT, title, list/map toggle RIGHT. Open state = full-width `GlassPill` input (inner magnifier, autofocus, ×) with the toggle keeping its slot, so one query still drives BOTH presentations across a view switch; Escape closes.
3. `MainTabScreenHeader` gained `.custom(child:)` (row-replacing, header still owns the geometry) and `leadingGlass` (default `true`) — Chats/Settings call sites untouched by design.
4. Trap paid: `InputDecoration.collapsed` only nulls `border`, so `RpgTheme.inputDecorationTheme.focusedBorder` painted a 2px box inside the glass capsule on focus; the field now sets `focusedBorder: InputBorder.none` explicitly.

## Verification
- `flutter analyze`: 0 issues. Full suite: **804 passed / 4 skips** (14 layout/interaction contracts + 7 search tests, incl. a `safeInsets.top == MainTabScreenHeader.clearance` no-band contract).
- Visual: real ContactsScreen via `test/preview/contact_network_preview.dart?screen=1` — cosmic/light/blue, 390×844 and 320×700, closed + open + live-filtered. Chats header re-verified via `glass_preview.dart`: unchanged. `graphify update .`: 9264 nodes.

## Notes for next session
- **Awaiting owner review on device.** Nothing merged: master untouched, no bump, no deploy from this session. Release path on his OK: PR `feat/contact-network` → master, bump 0.0.128 → **0.0.129** (PATCH, never `+N`), then `deploy-web.ps1` + `scripts/smoke/post-deploy-smoke.mjs`.
- Full detail: `2026-07-24-session-honeycomb-header-search.md`, `2026-07-23-handoff-honeycomb-search.md`, `2026-07-23-session-honeycomb-core.md` (all local-only).

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

---
### Prior latest ↓

**Date:** 2026-07-23 — PR #95 E2E cross-context ratchet repair deployed to production as frontend 0.0.126 / bundle `0486cb3`; backend intentionally unchanged.

## What was done
1. Created the branch from clean `origin/master`, restored only the 16 reviewed E2E production/test/runbook paths, and verified the diff contains no Contacts files.
2. Merged the 0.0.126 repair: origin-wide account+peer Web Locks, fail-closed missing-API behavior, exact-ciphertext replay, strict 40-record retention, web-only SharedPreferences coherence, provider message-id binding, and anonymized incident runbook.
3. Standards review found no hard documented-standard violation or correctness/concurrency defect; three non-blocking notes: the Web Locks test is vacuous under default VM tests, formatting churn inflates the diff, and lock-name strings could be centralized.
4. Spec review passed every incident requirement with no missing/partial behavior, scope creep, or unsafe implementation.

## Verification
- Isolated focused suite: **23 passed**; analyze: **0 issues**. Earlier full proof: Flutter **791 passed, 4 existing skips**, browser probe `SESSION_LOCK_PASS`, local full-stack Signal harness **11 passed**. PR CI passed both jobs. Production post-deploy smoke passed `/health`, `/version.json` 0.0.126, `/version`, literal bundle SHA `0486cb3`, and Flutter app boot. Graph: 9208 nodes.

## Notes for next session
- PR #95 is merged and deployed. Users must fully close and reopen the PWA; never clear site data. Live frontend is 0.0.126 / `0486cb3`; backend remains 0.0.123 / `4609af2`.
- Highest-value review follow-up: wire `session_cross_context_lock_web_test.dart` into a real Chrome CI lane when the project Chrome launcher is repaired. Manual source-controlled browser probe currently covers the JS boundary.
- Full: `2026-07-23-session.md`.

---
### Prior latest ↓

**Date:** 2026-07-22 — PR #94 merged into `master`; Appearance redesign and compact Settings website link released in frontend 0.0.125.

## What was done
1. Added a restrained FIREPLACE wordmark + localized “About” / “O projekcie” footer action immediately above the app-version block.
2. Wired `https://fireplace.ignorelist.com/welcome/` through `LaunchMode.externalApplication`, preserving the installed PWA.
3. Bumped frontend 0.0.124 → 0.0.125, merged PR #94 (`eb4ba89`), and deployed the resulting `master` bundle.

## Verification
- Focused Settings tests: 3 passed. Flutter analyze: 0 issues.
- Rendered Cosmic, Blue, Dark, Light, and Teal at 390×844 plus Light at 320×700.
- CI passed backend tests plus Flutter analyze/tests. Production smoke passed after the master deploy: health, frontend 0.0.125, bundle commit, Flutter boot. `graphify update .`: 9089 nodes.

## Notes for next session
- PR #94 is merged and the release is permanent on `master`; fully close/reopen the PWA after deployment, never clear site data.
- Full: `2026-07-22-session-settings-about-link.md`.

---



