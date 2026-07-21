# Session — landing `/welcome` polish nits (desktop + mobile)

**Date:** 2026-07-20
**Repo:** `C:/Users/Lentach/Desktop/fireplace-ping-deploy` · branch `master`
**Status:** LIVE in production (JS `Ctz2gedD` / CSS `CKHp0JYY`). Revised twice after
physical-phone feedback — see "Revision 2 / 3" below. Footer padding + skip + composer
all shipped. Mobile keyboard behavior still pending the owner's on-device sign-off.

## What was done
Six owner-reported nits, three desktop then three mobile.

### Desktop
1. **Footer dedup** — removed "built by one guy ·" from `<span class="f-made">`; the ledger
   strip already carries "built by one guy". Footer now shows only `github.com/Lentach`.
   File: `landing/src/pages/index.astro`.
2. **Skip the tour** — floating `Skip the tour ↓` pill (`.skip-tour`) that only shows while
   the journey owns the viewport and jumps to `#features` via Lenis. New button in
   `index.astro`, CSS in `landing.css`, scroll toggle + click in `main.ts`.
3. **Relay "mine" tag direction** — the row tag inside the relay window was hardcoded
   `"Bob's →"` on the left. Now direction-aware: forward `"Bob's →"` (left, IN port),
   reply `"← Kate's"` (right, OUT port), and the row's horizontal slide is mirrored by
   `dir`. `journey.ts` `buildTraveler` (label) + `update()` (side/slide).

### Mobile
4. **Hero terminal keyboard dismiss** — added a `Done` button (`.enc-done`) that appears on
   `:focus-within` and blurs the input (`stopPropagation` so the port's focus-on-click
   doesn't reopen it); Enter now also blurs. `encrypt.ts` + `landing.css`.
5. **Composer placeholder truncation** — the one-line phone composer clipped
   `"Type a message…"` to "Type a". Shortened to `"Message"` (real-chat authentic, fits the
   ~82px field). Both phones in `index.astro`.
6. **Journey device keyboard-aware focus** — focusing a phone composer used to fling the
   scroll-posed device around and hide it behind the keyboard. Now:
   - viewport meta gets `interactive-widget=resizes-visual` so the keyboard shrinks only the
     visual viewport (layout/sticky stage stay put — kills the layout jump at the root);
   - on focus (mobile, `innerWidth < 1000`) the journey **freezes** (`update()` early-returns)
     and `poseLifted()` lifts the focused device above the keyboard using
     `visualViewport.height`/`offsetTop`;
   - a `Done ✓` pill (`.kb-done`, shown via `body.kb-open`, positioned at the visible-band top)
     dismisses; blur unfreezes.
   `journey.ts` (state `kbLift`, focus/blur, `poseLifted`, freeze gate, Done wiring) +
   `index.astro` (button + meta) + `landing.css`.

## Key files
- `landing/src/pages/index.astro` — footer, placeholders, skip + Done buttons, viewport meta.
- `landing/src/scripts/main.ts` — skip-tour scroll/visibility + Lenis jump.
- `landing/src/scripts/journey.ts` — relay tag direction, keyboard freeze/lift/Done.
- `landing/src/scripts/encrypt.ts` — hero terminal Done + blur-on-Enter.
- `landing/src/styles/landing.css` — `.skip-tour`, `.enc-done`, `.kb-done`.

## Verification (local, headless)
- `npm run build` clean (JS 46.38 kB / gzip 16.12 kB).
- Footer reads `GITHUB.COM/LENTACH` only (screenshot).
- Skip pill: hidden at hero, shown mid-journey, hidden past it; click → `#features` in view.
- Relay tag: forward `"Bob's →"` left of row; reply `"← Kate's"` right of row (both confirmed
  by measured geometry after driving a forward send + reverse reply).
- Hero Done: hidden until focus, `display:flex` on focus, click blurs (status → Ready).
- Placeholder `"Message"` in an 82px field — fits, no clip.
- Journey freeze/lift: focus → `p` frozen, composer on-screen, `.kb-done` visible at top and
  hit-testable; freeze holds across a scroll; blur/Done release.

## Caveats / next
- Nits 4 & 6 are keyboard behaviors headless can't fully exercise (programmatic focus/blur
  don't always dispatch the event without OS window focus; a real keyboard can't be emulated).
  Logic was validated via dispatched events + real clicks; **needs physical-phone confirmation**.
- Dev-server HMR in this project does NOT reliably reload the client script/CSS — restart
  `landing` dev server after edits before trusting a browser check.
- Not deployed. To ship: `cd landing ; .\deploy-landing.ps1`, then verify HTML/CSS/JS 200s.
- Retained: footer `overflow-x: clip` autozoom fix and deploy-script permission/asset hardening.

## Revision 2 — footer spacing + first deploy (owner feedback)
- Footer padding evened + enlarged: `.f-row` `26px 6vw 34px` → `44px 6vw` (was cramped at the
  viewport bottom against the big outro void).
- First deploy shipped a STALE build: `npm ci` hit EPERM because the dev server locked
  rollup's `.node`, and PowerShell didn't halt on the native error (`Test-Path dist/index.html`
  passed on the old dist). **Always stop the `landing` dev server before `deploy-landing.ps1`**,
  and verify live asset bytes, not just the script's VERIFIED lines.

## Revision 3 — skip + mobile composer rebuild (owner feedback on-device, iOS)
Real-phone testing showed the skip pill colliding with the composer/rail, the prompt sub
clipping, and the freeze/lift SHRINKING the phone (unreadable), send dead, Done overlapping
the heading, background-tap not dismissing. Rebuilt:
- **Skip → nav pill.** Moved `.skip-tour` into `<nav>` (a `<button>`, so the `a:not(.cta)`
  mobile-hide rule doesn't touch it); shows only during the journey (main.ts `.show`). Being in
  the fixed nav, it never collides with journey overlays. Mobile nav gap tightened to fit
  FIREPLACE · SKIP TOUR · OPEN APP down to 320px.
- **Prompt sub** `.prompt p` shrunk on mobile (9.5px / .08em) so "press send — or just keep
  scrolling" never clips.
- **Composer = real chat.** `poseLifted` now pins the focused phone at FULL size (no shrink),
  `position: fixed` (`.phone.kb-lift`) so scroll/sticky can't move it, composer just above the
  keyboard (top clips off if the band is short), via `visualViewport`. "Compose mode" hides the
  surrounding chrome (`body.kb-open` → nav/prompt/cap/rail/hint `opacity:0 !important`) so the
  Done pill (top of the visible band) has nothing to overlap.
- **Send works:** send buttons `mousedown`-preventDefault (don't steal focus → no blur/reflow
  before the click lands), then send + `releaseKb()?.blur()` to dismiss.
- **Dismiss:** Done pill AND any `pointerdown` outside `.compose` release the freeze and blur.
- iOS note: `interactive-widget=resizes-visual` is Chrome-only (iOS ignores it) — the composer
  fix relies on `visualViewport`, which iOS honors. Kept the meta for Android consistency.

## Deploy state (end of 2026-07-20)
- LIVE: JS `Ctz2gedD`, CSS `CKHp0JYY`; live bytes verified (`kb-lift`, `body.kb-open nav`, nav
  `skip-tour`, `pointerdown`, `resizes-visual`).
- Changes are DEPLOYED but NOT committed to git (repo differs from production) — held for the
  owner's on-device sign-off of the mobile keyboard behavior before committing.

## Revision 4 — skip both-ways, dismiss guard, visibility (owner feedback)
- **Skip both ways.** `main.ts` skip is now context-aware: first ~70% of the journey shows
  "Skip tour ↓" → jumps to `#features`; the last ~30% shows "Skip back ↑" → scrolls up to
  `journey.offsetTop` (Bob's device / start). Shows through the reply phase now.
- **Dismiss refocus loop fixed.** The dismiss tap reflowed the phone out of `position:fixed`,
  and the tap's trailing click landed on the moved input → re-focused → keyboard reopened and
  wouldn't dismiss again. Added a `kbSuppressUntil` guard: `releaseKb` sets a 600ms window;
  the focus handler blurs+returns on any refocus inside it. Dismiss now sticks (Done + tap-out).
- **Skip more visible.** `.skip-tour` is now ice-tinted fill + bright border + soft glow
  (was a faint outline). Up-label kept short ("Skip back ↑") so the nav still fits at 320px.
- LIVE: JS `CstLs9Z4`, CSS `Bo8r84yF`. Still DEPLOYED-not-committed pending on-device sign-off.

## Revision 5 — skip bubble redesign + logo refresh (owner feedback)
- **Skip is no longer in the top bar.** It's now a round arrow bubble (`.skip-tour`, 46px,
  fixed bottom-center at ~11vh — where the journey's "…on its way" hint sits). Arrow flips with
  direction: `↓` jumps forward to `#features`, `↑` jumps back to `journey.offsetTop` (Bob's
  device). main.ts hides it during the two brief hint windows (`__journey` p/dir), so bubble
  and hint never share the spot.
- **Wordmark refreshes:** `nav .mark` → `location.reload()` (+ `cursor: pointer`).
- Removed the nav-pill skip styles and its mobile nav-gap tweak.
- LIVE: JS `BBM_IZQX`, CSS `Dp5F8pgJ`. Still DEPLOYED-not-committed pending on-device sign-off.

## Revision 6 — skip as a photon-pulse chevron (owner: "too big/generic, surprise me")
- Replaced the round bubble with a small **double-chevron SVG** (`.c1`/`.c2`) that pulses like
  a photon flowing down the wire — the site's core motif. Ice stroke + drop-shadow glow, no
  chrome; `@keyframes skipPulse` staggers the two chevrons for a directional "flow". Hover:
  glow ring, faster pulse, a 3px nudge in the skip direction. `prefers-reduced-motion` stills it.
- `.up` class rotates it 180° (skip back); main.ts toggles `.up` + aria-label instead of writing
  textContent (which would nuke the SVG). Applied the `frontend-design` skill.
- LIVE: JS `DPGsJey4`, CSS `D4pSIiHL`. Still DEPLOYED-not-committed pending on-device sign-off.
