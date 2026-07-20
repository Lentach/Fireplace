# Latest session summary

**Date:** 2026-07-19 (landing `/welcome` — automatic mobile shrink root fix — LIVE PRODUCTION)

## What was done
The recorded whole-page shrink was not relay animation or focus/double-tap zoom. Android Chrome reproduced it automatically with `visualViewport.scale === 1`: the layout viewport widened from 411px toward 500px and snapped back every seven seconds.

1. Isolated the source with JavaScript blocked and CSS motion A/B tests: the footer photon animates from `left: -8%` to `left: 104%` inside an overflow-visible wire, forcing mobile layout overflow.
2. Added `overflow-x: clip` to `footer`. The photon remains animated; its offscreen endpoint no longer widens the page.
3. Removed the ineffective mobile `touch-action: manipulation` workaround. Kept the independent 16px iOS editable-focus guard and the owner-approved visual-viewport navigation containment.
4. Rebuilt, reviewed, deployed, and verified the corrected artifact on production Android Chrome with trusted OS touch events.

## Key files
- `landing/src/styles/landing.css` — footer overflow root fix and obsolete gesture rule removal.
- `landing/src/scripts/main.ts` — visual-viewport navigation containment retained.
- `landing/deploy-landing.ps1` — production permission normalization and asset verification.
- Full write-up: `2026-07-19-session-landing-mobile-autozoom.md`.

## Verification
- Before fix: `innerWidth` repeatedly grew 411→498–502px while `clientWidth`, `visualViewport.width`, and `visualViewport.scale` stayed fixed.
- Minimal page: stable. Full landing without JavaScript: failed. All CSS motion disabled: stable. Only `.f-photon` disabled: stable.
- Final local and production Android traces each covered 9 seconds idle plus 9 seconds after a trusted double tap. `innerWidth === clientWidth === scrollWidth === 411` throughout; `visualViewport.scale === 1`; the 7-second `fphoton` animation continued.
- Production serves JS `0X9nz401` + CSS `mco4AcQr`; deploy verification returned HTTP 200 for HTML/CSS/JS.
- Desktop 1440×900 footer visual check passed with no horizontal overflow.
- Parallel Standards review: no findings. Spec review confirmed the source implementation; stale documentation/deployment findings were resolved before closeout.
- `/health`: `{"status":"ok","db":"ok"}`. Main PWA `/version.json`: `0.0.122`.
- `graphify update .`: 5,578 nodes, 7,306 edges, 419 communities.

## Notes for next session
- **LIVE:** `https://fireplace.ignorelist.com/welcome/` serves the footer-overflow root fix (`mco4AcQr`).
- Ask the owner for one physical-device confirmation.

## Previous
- 2026-07-19: Landing responsive journey polish + terminal plaintext input; source committed/pushed, not deployed. Full: `2026-07-19-session-landing-terminal-input.md`.
- 2026-07-19: Landing narrow/tablet journey switched to mobile below 1000px; master `228e0b6`, shipped to production (`CxSgh3lQ`). Full: `2026-07-19-session-landing-mobile-breakpoint.md`.
- 2026-07-17: Cosmic theme — 5th selectable theme, merged and shipped as 0.0.121. Full: `2026-07-17-session-cosmic-theme.md`.
- 2026-07-16: User card rounds 3+4 — PR #84 merged, 0.0.120 live. Full: `2026-07-16-session-user-card-round3.md`.
