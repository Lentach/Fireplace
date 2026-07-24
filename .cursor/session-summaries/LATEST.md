# Latest session summary

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
### Prior latest ↓

**Date:** 2026-07-22 — landing iOS keyboard-bounce RESOLVED on device (real culprit was the HERO Done, not the journey pill) + `fireplace-inbox` anti-spam push cooldown + inbox Clear button (`14e99fe`, deployed).

## What was done
1. **iOS keyboard bounce fixed for real** (`fireplaceWebsite` `ecdda29`, cleanup `4a158c8`, live JS `RXVEr5wJ`): the earlier journey-pill fixes were the wrong button — the HERO `.enc-done` (`encrypt.ts`) had the identical WebKit hole: pointerdown blur → pill hides → iOS synthesized click retargets to the textarea → NATIVE refocus (JS guards can't stop it; Blink cancels compat mouse events on pointerdown-preventDefault, WebKit doesn't — hence iOS-only). Fix: one-shot touchend `preventDefault` (disarmed on touchcancel) + 700ms `readOnly` hammer. **Confirmed working on the physical iPhone.** Journey-side guards kept (same hole there); `?kbdebug` tracer removed after confirmation.
2. **Hero `.enc-done` touch-gated** (`ed0b003`, live CSS `DBMb6rVT`): `@media (max-width: 999px)` → `and (pointer: coarse)` — no Done pill on narrow desktop; browser-verified both ways.
3. **fireplace-inbox anti-spam + Clear** (`14e99fe`, VM rebuilt, healthy): push cooldown max 1 ping/5min (suppressed messages still stored; next push says `(+N more)`; SW tag collapses banners) + key-gated `POST /contact/clear` (404 bad key / 204) + red-outline **Clear** button with confirm on the inbox page. `Store.clearMessages()` in db.ts.

## Verification
- Owner-device confirm on the hero fix; live-bundle greps each deploy; 818px/390px pill gating checked in browser.
- Inbox live sweep via VM: Clear button rendered; bad-key clear 404; two rapid POSTs → `1/1 delivered` + `suppressed (cooldown, 1 held)` (exactly one iPhone buzz); good-key clear 204 → 0 rows; **iPhone push subscription intact (1 row)**.

## Notes for next session
- **Local clone of `fireplace-inbox` now EXISTS** at `Desktop/fireplace-inbox` (no longer VM-only). Windows: `npm ci --ignore-scripts` (better-sqlite3 needs MSVC; tsc doesn't). Deploy = push, then VM `cd ~/fireplace-inbox && git pull && docker compose up -d --build`.
- Owner inbox URL unchanged (`/contact/inbox?key=547ac8b6…d071d95`); iPhone `web.push.apple.com` subscription lives in the `inbox-data` volume — do NOT delete.
- Full write-ups: `2026-07-22-session-ios-kb-bounce.md`, `2026-07-22-session-inbox-antispam.md`.

---

