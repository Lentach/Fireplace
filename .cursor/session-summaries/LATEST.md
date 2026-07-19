# Latest session summary

**Date:** 2026-07-19 (landing `/welcome` — narrow/tablet widths → mobile journey; keytag kept clear of the traveling capsule — master `228e0b6`, SHIPPED TO PROD)

## What was done
Owner reviewed the live landing journey at narrow desktop/tablet viewports: subtitles overlapped the relay black-hole cyphers (sec 04/05) and a docked device covered the wire arc (sec 06). Owner's call: "just make them mobile."

1. **Journey mobile breakpoint 700 → 1000.** `journey.ts` `const mobile = W < 1000` + CSS journey block `@media (max-width: 999px)`. On current master the desktop side-by-side crowded below ~940w (caption overlapped the relay sphere by 83–93px at 754/774). Now 754/774/984 render the single-device mobile journey; 1213/1568 desktop unchanged. The two hero rules (`.hero .content`, `.enc`) stayed in their own `@media (max-width: 700px)` block — they read fine at tablet sizes; only the journey graduates to ≤999.
2. **Keytag no longer covered by the encrypted capsule** (sec 02 + 06). In mobile every actor centers, so the keytag (parked under the centered device) landed on the traveler's hold point; on desktop it sits under the flank device, far from the center-held capsule. Fix (after the traveler `pos`/`scale` resolve, same-frame geometry): shove each keytag just below the LIVE capsule (`capBot+12`), gated by interval intersection so tall phones — tag naturally above the capsule — keep hugging the device, eased by arrival progress (`seg(p,0.08,0.14)` sender / `seg(p,0.78,0.84)` recipient). Owner chose the **clean fade-in** (capsule settles before the tag appears → collision-free, not an animated push).

## Key files
- `landing/src/scripts/journey.ts` — `mobile = W < 1000`; keytag positioning moved below the traveler-pose block, split from opacity.
- `landing/src/styles/landing.css` — journey `@media (max-width: 999px)`; new `@media (max-width: 700px)` block holds only `.hero .content` + `.enc`.
- Full write-up: `2026-07-19-session-landing-mobile-breakpoint.md`.

## Verification
- Headless Chromium (cache-bypassed, `window.__journey.p` scrub): 754/774 crowded on the OLD desktop path (gap −93/−83px); after the change 754/774/984 engage mobile, no caption↔sphere overlap; 1213/1568 unchanged. Keytag↔capsule bbox intersection = false at 774×676, 984×547, 390×844 (sec 06) and sec 02 when visible; desktop keytag untouched (shove 0). `astro build` clean (44 kB). `graphify update .` run.
- Prod (cache-busted): `/welcome/` references new bundle `CxSgh3lQ`; asset `200 application/javascript`; old bundle `404`; PWA `/` `200` (untouched); `/welcome` `301`→`/welcome/`.

## Notes for next session
- **Deploy hand-run** (mirrors `landing/deploy-landing.ps1`): `astro build` → scp `dist/*` to `~/fireplace/landing-staging-<stamp>/` → guarded atomic swap into `~/fireplace/landing-build/`. No nginx reload for content-only swap (`/welcome` block already installed).
- **Prod truth:** PWA 0.0.122, backend `077ce38` (0.0.120), landing `/welcome` = master `228e0b6`. Landing is Astro — no pubspec bump (that semver is the Flutter PWA only).
- Possible short-height edge (984×547 landscape): mobile top caption can lightly kiss the sphere top in sec 04/05 — pre-existing mobile vertical stacking, not owner-flagged; tall phones clean. If raised: nudge `.machine top` or shrink `.cap` at very short heights.
- **Worktree summary divergence (pre-existing):** the `C:/Users/Lentach/Desktop/fireplace` feature worktree holds an uncommitted `LATEST.md` with landing rounds 1–34, cosmic-login (0.0.121) and app-logo (0.0.122) deploys never committed to master. This record is committed to **master** (git-truth). Reconcile if it matters.

## Previous
- 2026-07-17: Cosmic theme — 5th selectable theme (space palette + animated dimming starfield chat bg, ported from the landing hero) via `RpgTheme.themeDataCosmic`/`CosmicBackdrop`/`GlassTheme.cosmic`/`starfield_background.dart`. MERGED to master + shipped as the cosmic front-door login (0.0.121). Full: `2026-07-17-session-cosmic-theme.md`.
- 2026-07-16: User card rounds 3+4 — **PR #84 MERGED (`077ce38`), 0.0.120 LIVE prod (web+backend, migration 0008)**. Aspect-sized hero, bigger manage sheet, plus-icon halo removed (`1c60cf6`). Full: `2026-07-16-session-user-card-round3.md`.
- 2026-07-16: Landing page prototypes → **B "Dot Globe" WON**, then MESSAGE JOURNEY won → production `/welcome` built (`landing/`, Astro + Lenis). Full: `2026-07-16-session-landing-prototype.md`.
- 2026-07-15: User card ROUND 2 — full-picture hero, tap-zone pager, **S2 "Frosted Backdrop" WON**, shared-media strip, drag-reorder photos (migration 0008/`POST /users/profile-photos/order`), linkified About. `0087150`. Full: `2026-07-15-session-user-card-round2.md`.
