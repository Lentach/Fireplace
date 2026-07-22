# Latest session summary

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
- 2026-07-22: Landing CONTACT FORM (cross-repo): backend `POST /contact` module (`contact_messages` mig 0009, throttle+honeypot, `notifyContact` account ping) + "Transmission · to the builder" panel on `/welcome`. Both LIVE (backend `8fe4951`, landing `12eb949`). **NOTE: this whole feature has since been extracted to `fireplace-inbox` (above) and removed from the monorepo.** Full: `2026-07-22-session-contact-form.md`.
- 2026-07-22: Landing Rev 16 (hero `.enc-done` → pointerdown pattern) + landing EXTRACTED to standalone **PUBLIC** repo `Lentach/fireplaceWebsite` (subtree split, 67 commits; business-card README with live-shot gallery; regenerated 1200×630 og.png; monorepo `landing/` removed, CLAUDE.md §2 pointer). Accepted exposure: deploy script publishes VM SSH login (key-only). Full: `2026-07-22-session-landing-extraction.md`.
- 2026-07-21: Pre-release audit-fix on branch `fix/audit-bugs`, v0.0.123 — R2 chat-detail dedup, backend branch cleanup, FULL test-suite audit (backend 474→534, frontend 727→770), link-preview ULA regex fix, MainShell nav-policy extraction. R1/R3 skipped per owner. Full: `2026-07-21-session-audit-fix-refactors.md`.
- 2026-07-20 (+07-22 Rev 16): Landing `/welcome` Rev 7-16 — reduced-motion + rAF pause + SEO meta + a11y + skip bookends; `.kb-done` journey pill dismisses+hides on **pointerdown** (Rev 15); Rev 16: hero `.enc-done` same pattern. Astro 7.x (dependabot). Full: `2026-07-20-session-landing-nits.md`.
