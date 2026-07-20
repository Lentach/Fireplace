# Landing mobile automatic shrink — footer overflow root fix

**Date:** 2026-07-19

## What was done

- Re-analyzed the 1.9-second, 720×1558 recording and reproduced the same whole-document shrink on Android Chrome: the layout viewport widened from 411px toward 500px, scaling the page toward the upper-left, then snapped back.
- Isolated the behavior without assumptions:
  - a minimal mobile page stayed at 411px;
  - the full landing still oscillated with all JavaScript blocked;
  - disabling CSS motion stopped it;
  - disabling only `.f-photon` stopped it.
- Found the exact 7-second source: `.f-photon` animates from `left: -8%` to `left: 104%` inside an overflow-visible wire. Mobile Chrome widened the layout viewport to contain the offscreen endpoint on every cycle.
- Added `overflow-x: clip` to `footer`. The photon still traverses the wire, but its offscreen paint can no longer enlarge document overflow.
- After the owner confirmed the root fix on the physical phone, removed every superseded zoom mitigation: mobile `touch-action`, forced 16px textarea/composer metrics, visual-viewport CSS variables, and the JavaScript navigation synchronizer. Navigation, composers, and input sizing are back to their pre-investigation implementation.
- Kept the deploy-script permission normalization and asset verification because they independently prevent the real mode-700/HTTP-403 publish failure exposed during deployment.
- Deployed the cleaned root-only implementation to production.

## Key files

- `landing/src/styles/landing.css` — footer overflow containment is the only retained page fix.
- `landing/deploy-landing.ps1` — readable staging permissions and CSS/JS post-deploy verification retained as deployment reliability work.
- `graphify-out/GRAPH_REPORT.md`, `graphify-out/graph.json` — refreshed after cleanup.

## Verification

- Before the fix, Android Chrome repeatedly changed `innerWidth` from 411px up to 498–502px while `documentElement.clientWidth`, `visualViewport.width`, and `visualViewport.scale` stayed fixed.
- A no-JavaScript landing still reproduced; a minimal page did not. Disabling all CSS animation stabilized it. Disabling only `.f-photon` also held `innerWidth` and `scrollWidth` at 411px for longer than its 7-second cycle.
- With `footer { overflow-x: clip }`, the live `fphoton` animation continued across approximately `-32px` to `426px` while layout and document widths stayed fixed.
- The owner confirmed the production root fix works on the physical phone.
- Cleaned local mobile preview, 9 seconds: `innerWidth` stayed 412px; `clientWidth === scrollWidth === 397px`; photon animation remained active across `-29px` to `412px`.
- Cleanup proof: `--visual-viewport-left` is absent, navigation is again `left: 0; right: 0`, hero textarea is 15px, and phone textarea is 10px.
- Production Astro build passed: one route, JS 45.08 kB / 15.69 kB gzip (`C8QXiHN_`).
- Production serves CSS `C5BUuC4w` and JS `C8QXiHN_`; HTML, CSS, and JS returned HTTP 200.
- Cleaned production mobile trace, 9 seconds: `innerWidth` stayed 412px; `clientWidth === scrollWidth === 397px`; the footer remained clipped and the 7-second photon animation remained active. Zero console/page errors.
- `/health` returned `{"status":"ok","db":"ok"}`; main PWA `/version.json` remained `0.0.122`.
- `graphify update .`: 5,578 nodes, 7,306 edges, 420 communities.

## Notes for next session

- **LIVE:** `https://fireplace.ignorelist.com/welcome/` serves the root-only footer fix in CSS `C5BUuC4w`.
- The footer clip is the only retained page behavior change from the zoom investigation. Deploy hardening remains separately justified by the observed asset-permission failure.
