# Latest session summary

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
### Prior latest ↓

**Date:** 2026-07-22 — GIPHY attribution mark added to the GIF picker + web redeployed to **0.0.124** with a fresh, valid Giphy client key (GIF search restored on prod).

## What was done
1. **Official GIPHY attribution mark** in the GIF picker (`frontend/lib/widgets/gif_picker_sheet.dart`) — replaced plain `Text('Powered by GIPHY')` with `Powered by` + GIPHY's official logo image, theme-aware (white on dark / black on light via `Theme.of(context).brightness`); `errorBuilder` falls back to bold `GIPHY` text. Needed for the Giphy API **Beta→Production** upgrade (form requires the mark + a demo video).
2. **Bundled assets** `frontend/assets/giphy/giphy_logo_{white,black}.png` (registered in pubspec) — derived from GIPHY's own official logo (`Giphy/GiphyAPI` → `logo_buildtext_white_forever.gif`, last frame, white-bg keyed to alpha, mono-recolored). **CAVEAT**: self-composed lockup (label + official logo), NOT the exact Giphy attribution-pack PNG — drop-in swap path in the session file.
3. **Version 0.0.123 → 0.0.124** (`frontend/pubspec.yaml`); committed `462c797`, pushed to master. Backend untouched (still 0.0.123 / `4609af2`).
4. **Web redeployed** via `deploy-web.ps1` after owner added `$GiphyApiKey` (valid, 32-char) to gitignored `deploy-web.config.ps1`.

## Verification
- `dart analyze` clean; `flutter build web` → `commit=462c797, version=0.0.124`, published (atomic swap).
- Prod `/version.json` = **0.0.124**; served `main.dart.js` contains `462c797` (not stale); mark PNGs `/assets/assets/giphy/*` → 200.
- **Giphy key valid**: `api.giphy.com` trending `status:200/OK`, real `search?q=hello` → 200 → **GIF search restored** (was dead since the old key was revoked).

## Notes for next session
- **Giphy Production upgrade still pending OWNER action**: record the demo video from the LIVE app (Beta key works, ~42/hr) showing GIF search + a GIF being sent + the "Powered by GIPHY" mark, then submit via the dashboard. **Production-upgrade the key** or it 429s under real traffic.
- **Exact-mark swap (optional)**: overwrite `giphy_logo_black.png` (dark lockup → light theme) + `giphy_logo_white.png` (white → dark theme) with the official "Powered By GIPHY" PNGs from the form's download link — same filenames, zero code change; if they bake in "Powered by", also drop the separate `Powered by` Text.
- After deploy: fully close+reopen the PWA (never uninstall — wipes E2E keys). Deploy is single-worktree now (`Desktop/Fireplace` on master holds `deploy-web.ps1` + gitignored config).
- Full write-up: `2026-07-22-session-giphy-attribution-web-deploy.md`.

---

## Previous
- 2026-07-22: Contact inbox EXTRACTED to standalone PRIVATE `Lentach/fireplace-inbox` (Fastify+SQLite on VM :3001, nginx flip, monorepo cutover `4609af2` v0.0.123, tests 534/47) + security-hardened `9efae5c` after independent review + landing "Anti-Quantum Notes" card. Full: `2026-07-22-session-inbox-extraction.md`.
