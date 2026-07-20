# Landing mobile automatic page-zoom fix

**Date:** 2026-07-19

## What was done

- Analyzed the 1.9-second, 720×1558 mobile Safari recording at 0.05-second intervals.
- Measured fixed page elements, the section-04 caption, relay core, and journey rail. The whole document shrinks around the web viewport's top-left origin, then snaps back; Safari chrome does not scale.
- Added both accessible browser-side mitigations under the existing mobile breakpoint:
  - `touch-action: manipulation` disables double-tap page zoom while preserving one-finger panning and pinch zoom.
  - Every focusable landing textarea now renders at 16px, preventing browser focus-zoom on undersized editable text. The phone composer uses a compact 1.05 line height and an 84px cap so multi-line input remains contained.
- Kept the viewport metadata unchanged: `width=device-width, initial-scale=1`. No `maximum-scale`, `user-scalable=no`, or `touch-action: none` restriction was introduced.
- Made the fixed navigation follow `visualViewport.offsetLeft/width`, so OPEN APP remains inside the actually visible page area during a browser scale transition instead of staying anchored to the wider layout viewport.
- Checked the reported console output. `content-script.js`, `inpage.js`, MetaMask, `ObjectMultiplex`, and `runtime.lastError` messages are injected by browser extensions; a clean browser produced no landing console errors.
- Removed all temporary frame extracts, contact sheets, and verification screenshots.
- Deployed the landing to production after parallel standards/spec reviews returned no findings. Hardened the deploy script to normalize staging permissions and verify every emitted CSS/JS asset, after the first publish exposed an `assets/` directory mode of `700`.

## Key files

- `landing/src/styles/landing.css`, `landing/src/scripts/main.ts` — mobile zoom guards and visual-viewport-bound navigation.
- `graphify-out/GRAPH_REPORT.md`, `graphify-out/graph.json` — refreshed after the source change.
- `landing/deploy-landing.ps1` — readable staging permissions and asset-level post-deploy verification.

## Verification

- Recording measurements: static logo width fell from 181px to 147px, CTA width from 208px to 169px, and relay width from 548px to 439px (about 0.81×), then the whole page returned to its original scale in one source frame at 1.4s. Browser chrome stayed fixed. This rules out a relay-only `vh`/canvas/CSS animation.
- Browser verification at 390×844:
  - computed `touch-action` is `manipulation`;
  - hero and phone textareas compute to 16px;
  - viewport metadata remains unrestricted;
  - hero typing, sender send, section-04 scrolling, recipient typing, long-input capping, and clear/shrink behavior all completed at `visualViewport.scale === 1` with `scrollX === 0`.
  - focused sender textarea remained active and enabled through the section-04 scroll path, exercising the focus-retention state that previously exposed browser focus zoom.
- Short-landscape 984×547 render checked; the outer phone geometry remains unchanged because the fix only changes content inside the fixed-aspect phone.
- Production `astro build` completed: one route, client bundle 45.38 kB / 15.80 kB gzip (`0X9nz401`).
- Built-preview scale regression at 412×915 covered page scales 1.0, 1.23, and 1.5. OPEN APP stayed fully within the visual viewport at every scale; the 1.23 case changed from clipped (`right 376 > visible 323`) to contained (`right 302 < visible 323`).
- Clean reload and scale transitions produced zero console messages/page errors. No landing source contains the extension error identifiers shown in the owner's console.
- Production deploy published bundle `0X9nz401` and stylesheet `77H8Y7N2`. The hardened second deploy verified HTML, CSS, and JS as HTTP 200.
- Production browser at 412×915 rendered the full styled page with zero console/page errors. OPEN APP remained contained at scales 1.0, 1.23, and 1.5; the focused sender→section-04 journey completed with `visualViewport.scale === 1` and `scrollX === 0`.
- Post-deploy `/health` returned `{"status":"ok","db":"ok"}` and `/version.json` remained `0.0.122`, confirming the main app stayed intact.
- `graphify update .` completed: 5,578 nodes, 7,306 edges, 418 communities.

## Notes for next session

- **LIVE:** `https://fireplace.ignorelist.com/welcome/` serves bundle `0X9nz401` with the mobile zoom and visual-viewport navigation fixes.
- Trusted real-device gesture confirmation is still useful; if any device still scales, capture `visualViewport.scale/width/height`, `innerWidth/innerHeight`, `scrollY`, and `document.activeElement`.
