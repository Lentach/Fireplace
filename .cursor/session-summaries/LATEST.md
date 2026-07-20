# Latest session summary

**Date:** 2026-07-19 (landing `/welcome` — root-only mobile shrink fix — LIVE PRODUCTION)

## What was done
The recorded whole-page shrink was not relay animation or focus/double-tap zoom. Android Chrome reproduced it automatically with `visualViewport.scale === 1`: the layout viewport widened from 411px toward 500px and snapped back every seven seconds.

1. Isolated the source with JavaScript blocked and CSS motion A/B tests: the footer photon animates from `left: -8%` to `left: 104%` inside an overflow-visible wire, forcing mobile layout overflow.
2. Added `overflow-x: clip` to `footer`. The photon remains animated; its offscreen endpoint no longer widens the page.
3. Owner confirmed the production fix works on the physical phone.
4. Removed every superseded mitigation: mobile `touch-action`, forced textarea/composer sizing, visual-viewport CSS variables, and the JavaScript nav synchronizer. Only the footer clip remains as a page fix.
5. Retained deploy permission normalization and asset verification because they prevent the independently observed mode-700/HTTP-403 publish failure.

## Key files
- `landing/src/styles/landing.css` — root-only footer overflow fix.
- `landing/deploy-landing.ps1` — production permission normalization and asset verification.
- Full write-up: `2026-07-19-session-landing-mobile-autozoom.md`.

## Verification
- Before fix: `innerWidth` repeatedly grew 411→498–502px while `clientWidth`, `visualViewport.width`, and `visualViewport.scale` stayed fixed.
- Minimal page: stable. Full landing without JavaScript: failed. All CSS motion disabled: stable. Only `.f-photon` disabled: stable.
- Cleaned production trace ran longer than the 7-second animation: `innerWidth` stayed 412px, `clientWidth === scrollWidth === 397px`, and `fphoton` remained active.
- Cleanup verified live: no visual-viewport custom property, nav restored to normal fixed edges, hero textarea 15px, phone textarea 10px.
- Production serves JS `C8QXiHN_` + CSS `C5BUuC4w`; deploy verification returned HTTP 200 for HTML/CSS/JS.
- Clean production browser console: zero messages/page errors.
- `/health`: `{"status":"ok","db":"ok"}`. Main PWA `/version.json`: `0.0.122`.
- `graphify update .`: 5,578 nodes, 7,306 edges, 420 communities.

## Notes for next session
- **LIVE:** `https://fireplace.ignorelist.com/welcome/` serves the root-only footer fix (`C5BUuC4w`).

## Previous
- 2026-07-19: Landing responsive journey polish + terminal plaintext input; source committed/pushed, not deployed. Full: `2026-07-19-session-landing-terminal-input.md`.
- 2026-07-19: Landing narrow/tablet journey switched to mobile below 1000px; master `228e0b6`, shipped to production (`CxSgh3lQ`). Full: `2026-07-19-session-landing-mobile-breakpoint.md`.
- 2026-07-17: Cosmic theme — 5th selectable theme, merged and shipped as 0.0.121. Full: `2026-07-17-session-cosmic-theme.md`.
- 2026-07-16: User card rounds 3+4 — PR #84 merged, 0.0.120 live. Full: `2026-07-16-session-user-card-round3.md`.
