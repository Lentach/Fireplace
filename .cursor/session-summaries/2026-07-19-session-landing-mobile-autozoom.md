# Landing mobile automatic page-zoom fix

**Date:** 2026-07-19

## What was done

- Analyzed the 1.9-second, 720×1558 mobile Safari recording at 0.05-second intervals.
- Measured fixed page elements, the section-04 caption, relay core, and journey rail. The whole document shrinks around the web viewport's top-left origin, then snaps back; Safari chrome does not scale.
- Added both accessible browser-side mitigations under the existing mobile breakpoint:
  - `touch-action: manipulation` disables double-tap page zoom while preserving one-finger panning and pinch zoom.
  - Every focusable landing textarea now renders at 16px, preventing browser focus-zoom on undersized editable text. The phone composer uses a compact 1.05 line height and an 84px cap so multi-line input remains contained.
- Kept the viewport metadata unchanged: `width=device-width, initial-scale=1`. No `maximum-scale`, `user-scalable=no`, or `touch-action: none` restriction was introduced.
- Removed all temporary frame extracts, contact sheets, and verification screenshots.

## Key files

- `landing/src/styles/landing.css` — mobile gesture policy and focus-safe textarea sizing.
- `graphify-out/GRAPH_REPORT.md`, `graphify-out/graph.json` — refreshed after the source change.

## Verification

- Recording measurements: static logo width fell from 181px to 147px, CTA width from 208px to 169px, and relay width from 548px to 439px (about 0.81×), then the whole page returned to its original scale in one source frame at 1.4s. Browser chrome stayed fixed. This rules out a relay-only `vh`/canvas/CSS animation.
- Browser verification at 390×844:
  - computed `touch-action` is `manipulation`;
  - hero and phone textareas compute to 16px;
  - viewport metadata remains unrestricted;
  - hero typing, sender send, section-04 scrolling, recipient typing, long-input capping, and clear/shrink behavior all completed at `visualViewport.scale === 1` with `scrollX === 0`.
  - focused sender textarea remained active and enabled through the section-04 scroll path, exercising the focus-retention state that previously exposed browser focus zoom.
- Short-landscape 984×547 render checked; the outer phone geometry remains unchanged because the fix only changes content inside the fixed-aspect phone.
- Production `astro build` completed: one route, client bundle 45.08 kB / 15.69 kB gzip.
- Built preview at `127.0.0.1:4330/welcome/` exposed the same computed gesture/font rules and completed the focused sender → relay flow.
- `graphify update .` completed: 5,577 nodes, 7,305 edges, 416 communities.

## Notes for next session

- The source fix is committed/pushed but not deployed. Production deployment still requires explicit owner approval.
- Headless Chromium cannot generate trusted browser double-tap/pinch/focus zoom, so the original iOS/Android device reproduction still needs one real-device confirmation after deployment or through a LAN preview.
- If any real device still scales, capture `visualViewport.scale/width/height`, `innerWidth/innerHeight`, `scrollY`, and `document.activeElement` during the event before changing layout code again.
