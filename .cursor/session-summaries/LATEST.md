# Latest session summary

**Date:** 2026-07-19 (landing `/welcome` — mobile automatic page-zoom fix — LIVE PRODUCTION)

## What was done
The 1.9-second 720×1558 Safari recording proves a browser page-scale loop, not a relay-core animation: every fixed page element shrinks around the web viewport's top-left origin to about 0.81×, then snaps back, while Safari chrome stays fixed.

1. Mobile `html`/`body` now use `touch-action: manipulation`, blocking double-tap page zoom while preserving one-finger scrolling and pinch zoom.
2. Every mobile landing textarea renders at 16px, removing the undersized-editable focus-zoom path. The mock phone composer keeps compact multiline metrics and a bounded internal scroll area.
3. Viewport metadata remains accessibility-safe: `width=device-width, initial-scale=1`; no scale cap or `user-scalable=no`.
4. Fixed navigation now tracks the live visual viewport, keeping OPEN APP visible while browser page scale changes. The reported console errors are MetaMask/extension content-script failures, not landing errors.
5. Landing deployment now normalizes staging permissions and verifies emitted CSS/JS assets, preventing a superficially successful HTML-only publish with unreadable assets.

## Key files
- `landing/src/styles/landing.css`, `landing/src/scripts/main.ts` — mobile zoom guards and visual-viewport-bound navigation.
- `graphify-out/GRAPH_REPORT.md`, `graphify-out/graph.json` — refreshed graph.
- `landing/deploy-landing.ps1` — production permission normalization and asset verification.
- Full write-up: `2026-07-19-session-landing-mobile-autozoom.md`.

## Verification
- Frame measurement: logo 181→147px, CTA 208→169px, relay 548→439px, then full reset at 1.4s; browser chrome unchanged.
- Responsive browser at 390×844: hero/sender/recipient typing, long-input cap, clear/shrink, sender send, focused scroll to section 04, and fresh-page scroll. Computed `touch-action: manipulation`, both textarea classes 16px, `visualViewport.scale === 1`, `scrollX === 0`.
- Reproduced OPEN APP clipping at 412×915 and scale 1.23 (`right 376 > visible 323`); after binding nav to the visual viewport, the CTA remained contained through scales 1.0–1.5 (`right 302 < visible 323` at 1.23).
- Clean browser console: zero messages/page errors. Screenshot errors originate from extension `content-script.js`/`inpage.js`/MetaMask, not landing source.
- Built preview repeated the focused sender→relay and scaled-nav flows. `astro build` clean: 45.38 kB / 15.80 kB gzip (`0X9nz401`).
- Production serves JS `0X9nz401` + CSS `77H8Y7N2`. At 412×915 the styled page had zero console/page errors; CTA containment passed scales 1.0/1.23/1.5 and the focused sender→relay flow stayed at scale 1 with no horizontal scroll.
- Deploy script's first run exposed `assets/` mode `700`; production was immediately repaired to `755`, the script was hardened with `chmod -R a+rX`, and the second deploy verified HTML/CSS/JS HTTP 200.
- `/health` remained `{"status":"ok","db":"ok"}`; main PWA `/version.json` remained `0.0.122`.
- `graphify update .`: 5,578 nodes, 7,306 edges, 418 communities.

## Notes for next session
- **LIVE:** `https://fireplace.ignorelist.com/welcome/` serves the mobile zoom/nav fix (`0X9nz401`).
- One real iOS/Android gesture pass remains useful because headless Chromium cannot emit trusted double-tap/pinch/focus zoom.

## Previous
- 2026-07-19: Landing responsive journey polish + terminal plaintext input; source committed/pushed, not deployed. Full: `2026-07-19-session-landing-terminal-input.md`.
- 2026-07-19: Landing narrow/tablet journey switched to mobile below 1000px; keytags kept clear of the traveling capsule. Master `228e0b6`, shipped to production (`CxSgh3lQ`). Full: `2026-07-19-session-landing-mobile-breakpoint.md`.
- 2026-07-17: Cosmic theme — 5th selectable theme, merged and shipped as 0.0.121. Full: `2026-07-17-session-cosmic-theme.md`.
- 2026-07-16: User card rounds 3+4 — PR #84 merged, 0.0.120 live. Full: `2026-07-16-session-user-card-round3.md`.
