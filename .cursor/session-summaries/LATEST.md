# Latest session summary

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

**Date:** 2026-07-23 — Contacts tab remains unfinished on `feat/contact-network`: circular local node + clipped-square contact terminals, PCB dogleg traces, deterministic elliptical layout, drag-to-pin, and list fallback toggle.

## What was done
1. New `ContactNetworkView`: pure re-render of `FriendsProvider.friends` — no fake nodes/status; doubled traces = real conversations; hero composition for the one-contact state; ticks/orbits/brackets aesthetic, theme tokens only.
2. Deterministic measured layout (viewport + textScaler), elliptical rings; collision-free in validated fitted/long-label/dense layouts (ring candidates + full-bounds sweep, contract-tested; least-overlap fallback for exhausted cases). Per-user SharedPreferences pin hints (clamped, collision-resolved per build); InteractiveViewer for dense maps with keyboard focus reveal.
3. A11y as core invariant: per-node semantic buttons (`container: true` — labels otherwise merge into one blob), sorted traversal, Tab/Enter, 48dp floor, reduce-motion static.
4. `MainTabScreenHeader` title now truly centered via Stack + `Positioned` side controls.
5. `ContactsScreen` is a StatefulWidget with network default and a classic-list fallback; card/chat/pending-open flows remain untouched.

## Verification
- Analyze 0 issues; full suite **786 passed** including 10 new contract tests. Visual loop covered all five themes, 0/1/8/25 contacts, narrow/desktop widths, and textScale 1.6.

## Notes for next session
- The earlier `c15d770` feature-branch test bundle was superseded by the production 0.0.126 E2E deploy. The network remains branch-only and must not be merged or redeployed until owner review.
- Next work: replace rejected 40-contact dense map mode with the Terminal Rack patch-panel grid, plus map-mode jitter fade. Full local spec: `2026-07-23-handoff-terminal-rack.md`.
- Trap: `flutter run -d web-server` hot restart does not recompile `-t` entry-file changes; cold restart is required.
- Full: `2026-07-23-session-contact-network.md`.

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
### Prior latest ↓

**Date:** 2026-07-22 — Appearance settings redesign completed and deployed for device testing from `feat/appearance-redesign` (`f5c9aa6`): one coherent theme/background model, real previews, and Cosmic Theme default → starfield.

## What was done
1. Replaced the cramped five-icon Theme tile, misleading Plain/Glyphs tile, and Cosmic-only Starfield switch with one preview-backed **Appearance** entry and a dedicated selector screen.
2. Added one per-user preference: Theme default / Plain / Hieroglyphs. Cosmic + Theme default resolves to the animated starfield; explicit overrides persist across theme changes. Auth keeps its forced Cosmic starfield independently.
3. Added real miniature chat previews, safe legacy migration, English/Polish strings, focused tests, narrow-width top-bar handling, and a scroll fade that prevents cross-theme previews bleeding through floating chrome.
4. Published the feature-branch frontend bundle to production as an ephemeral test deploy; master/backend remain untouched.

## Verification
- Flutter analyze: 0 issues. Full Flutter suite: 775 passed, 4 existing skips. `graphify update .`: 9081 nodes.
- Rendered all five themes at 390×844 and Cosmic at 320×700. Read-only design review: mergeable; follow-up confirmed both requested visual fixes.
- Production smoke passed: `/health`, `/version.json`, `/version`, served bundle contains `f5c9aa6`, and Flutter boot rendered.

## Notes for next session
- Feature-branch bundle `f5c9aa6` is live for owner testing. No version bump and no master merge; production permanence still requires explicit approval.
- Full: `2026-07-22-session-appearance-redesign.md`.

---



