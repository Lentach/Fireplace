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
- Removed the ineffective mobile `touch-action: manipulation` mitigation. Kept the 16px textarea rules because they independently prevent iOS editable-focus zoom, and kept visual-viewport-bound navigation because it preserves OPEN APP during legitimate pinch zoom.
- Deployed the corrected landing to production using the hardened asset-verifying deploy script.

## Key files

- `landing/src/styles/landing.css` — footer overflow containment; obsolete double-tap rule removed.
- `landing/src/scripts/main.ts` — visual-viewport-bound navigation retained.
- `landing/deploy-landing.ps1` — readable staging permissions and CSS/JS post-deploy verification retained.
- `graphify-out/GRAPH_REPORT.md`, `graphify-out/graph.json` — refreshed after the source change.

## Verification

- Before the fix, Android Chrome repeatedly changed `innerWidth` from 411px up to 498–502px while `documentElement.clientWidth`, `visualViewport.width`, and `visualViewport.scale` stayed fixed.
- A no-JavaScript landing still reproduced; a minimal page did not. Disabling all CSS animation stabilized it. Disabling only `.f-photon` also held `innerWidth` and `scrollWidth` at 411px for longer than its 7-second cycle.
- With `footer { overflow-x: clip }`, the live `fphoton` animation continued across approximately `-32px` to `426px` while `innerWidth` and document `scrollWidth` remained 411px.
- Final local Android build, full JavaScript enabled:
  - 9 seconds idle: `innerWidth === clientWidth === scrollWidth === 411`;
  - trusted Android double tap followed by 9 seconds: all three widths still 411, `visualViewport.scale === 1`;
  - the `fphoton` animation remained active throughout.
- Desktop 1440×900 visual check passed; the footer photon remained visible and animated, with no horizontal document overflow.
- Production Astro build passed: one route, JS 45.38 kB / 15.80 kB gzip (`0X9nz401`).
- Production deployed CSS `mco4AcQr` and JS `0X9nz401`; HTML, CSS, and JS returned HTTP 200.
- Production Android Chrome repeated the 9-second idle and 9-second post-double-tap traces: `innerWidth`, `clientWidth`, and `scrollWidth` stayed 411px. ADB-delivered touch/click/`dblclick` events all reported `isTrusted === true`; zero runtime/log protocol errors occurred.
- Parallel review: Standards returned no findings. Spec confirmed the source fix was compliant; its stale-doc/not-yet-deployed findings were resolved by this deploy and summary rewrite. Deploy hardening remains intentionally because the previous production publish exposed unreadable mode-700 assets.
- `/health` returned `{"status":"ok","db":"ok"}`; main PWA `/version.json` remained `0.0.122`.
- `graphify update .`: 5,578 nodes, 7,306 edges, 419 communities.

## Notes for next session

- **LIVE:** `https://fireplace.ignorelist.com/welcome/` serves CSS `mco4AcQr` with the footer-overflow root fix.
- The relay, Lenis, textarea focus, and browser `visualViewport.scale` were not the automatic shrink source. The 7-second footer photon overflow was.
- Ask the owner for one physical-device confirmation; the production artifact has passed a real Android Chrome target with trusted OS touch events.
