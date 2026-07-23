# Latest session summary

**Date:** 2026-07-23 — Contacts tab redesigned as a **contact network node map** on branch `feat/contact-network` (bundle `c15d770` live as an ephemeral test deploy, NOT merged): circular local node + clipped-square contact terminals, PCB dogleg traces, deterministic elliptical layout, drag-to-pin, list fallback toggle.

## What was done
1. New `ContactNetworkView`: pure re-render of `FriendsProvider.friends` — no fake nodes/status; doubled traces = real conversations; hero composition for the one-contact state; ticks/orbits/brackets aesthetic, theme tokens only.
2. Deterministic measured layout (viewport + textScaler), elliptical rings; collision-free in validated fitted/long-label/dense layouts (ring candidates + full-bounds sweep, contract-tested; least-overlap fallback for exhausted cases). Per-user SharedPreferences pin hints (clamped, collision-resolved per build); InteractiveViewer for dense maps with keyboard focus reveal.
3. A11y as core invariant: per-node semantic buttons (`container: true` — labels otherwise merge into one blob), sorted traversal, Tab/Enter, 48dp floor, reduce-motion static.
4. `MainTabScreenHeader` title now truly centered via Stack + `Positioned` side controls (old `Expanded` row drifted it; non-positioned `Align` in Stack collapses to center — trap).
5. `ContactsScreen` → StatefulWidget: network default, header trailing toggle to the classic list; card/chat/pending-open flows untouched. 8 new ARB keys en+pl (template is `app_pl.arb`).

## Verification
- Analyze 0 issues; full suite **786 passed** incl. 10 new contract tests. Visual loop: all five themes (cosmic/blue/dark/light/teal) × 0/1/8/25 contacts × 390/320/1100px + textScale 1.6; Chats header re-verified via glass_preview. `graphify`: 9179 nodes.

## Notes for next session
- Branch bundle `c15d770` is LIVE for owner device testing (smoke passed: 0.0.125 + bundle sha + boot). No version bump for the ephemeral test deploy (2026-07-22 precedent); owner review → PR → merge + PATCH bump still pending. Fully close/reopen the PWA — never clear site data.
- Trap: `flutter run -d web-server` hot restart does not recompile `-t` entry-file changes — cold restart required.
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

## Previous
- 2026-07-22: GIPHY attribution mark in GIF picker + web 0.0.124 with fresh valid Giphy key (GIF search restored). Full: `2026-07-22-session-giphy-attribution-web-deploy.md`.
- 2026-07-22: Contact inbox EXTRACTED to standalone PRIVATE `Lentach/fireplace-inbox` (Fastify+SQLite on VM :3001, nginx flip, monorepo cutover `4609af2` v0.0.123, tests 534/47) + security-hardened `9efae5c` after independent review + landing "Anti-Quantum Notes" card. Full: `2026-07-22-session-inbox-extraction.md`.
