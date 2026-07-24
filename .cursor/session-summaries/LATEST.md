# Latest session summary

**Date:** 2026-07-24 — PWA logout incident root-caused: server auth CONFIRMED healthy (112/112 refreshes 201 over 14 days, zero rejections); the owner-verified victim was proven via Postgres xmin forensics to have suffered a FULL device-side origin-storage wipe — tokens AND Signal identity destroyed and regenerated on re-login (permanent history loss on that device).

## What was done
1. Ruled out server causes with live VM evidence: `/auth/refresh` deployed + 100% successful; most users hold healthy 365-day sliding sessions; no `[auth-session-end]` warns; secret rotation/clock/CORS refuted.
2. "Logged out after 1 day+" = 24h access-JWT TTL on devices that never call refresh. DB fingerprint: victims' rows never slide (`expires_at` = `created_at`+365d exactly). Top churner was owner's incognito build checks (noise).
3. Verified logout path is E2E-key-safe at source: only `jwt_token`/`refresh_token` removed; re-login reuses on-device Signal store.

## Verification
- Read-only: file:line reads + nginx/docker/psql queries on the VM. No code changes, no deploys.

## Notes for next session
- Open: owner's "more common than usual" uptick not visible server-side. Shortlist: stale PWA bundle (invisible server-side), per-device origin-storage eviction (would also wipe Signal keys), iOS 26 behavior. Waiting on victim capture: Settings footer `version · gitCommit` + do old chats decrypt after re-login.
- Proposed `fix/pwa-logout` hardening (needs owner OK): version telemetry header, session-end reason on login screen, proactive refresh on cold boot, `navigator.storage.persist()` at login, in-app update nudge. NEVER clear site data / rotate JWT_SECRET.
- Full: `2026-07-24-session.md`.

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


