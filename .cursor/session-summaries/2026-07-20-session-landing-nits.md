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

## Revision 7 — the four "what else can we improve" items (reduced-motion, off-screen rAF pause, social/SEO meta, a11y)
Not owner nits — the four next-step improvements flagged at the end of the nit work, done together.

1. **Reduced motion (`prefers-reduced-motion: reduce`).** The engine already separates
   scroll-time (`p`, reversible, user-driven) from ambient-time (`t`, "stars class"); reduced
   motion freezes only `t`, so the scroll-driven journey stays live.
   - Canvas: globe + outro render a SINGLE static frame (no rAF loop); the globe still redraws
     on drag/zoom/resize (user-driven motion kept). `journey.ts` freezes ambient `t` (stars
     twinkle, shell flicker, wire photons, rotor ambient spin) and skips the cipher scramble
     churn (`!reduce` guards on the two settle conditions) while STILL tracking scroll.
     `const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches` in
     `globe.ts` / `main.ts` / `journey.ts` (`encrypt.ts` already had it).
   - CSS: one consolidated `@media (prefers-reduced-motion: reduce)` block stills the remaining
     ambient keyframes (`cue`, `caretblink` c-caret, `dp` dotpulse/kdot/slit, `nuc`, `fphoton`,
     `land`). The encrypt caret/status and the skip chevron were already covered.
2. **Pause off-screen rAF loops** (CPU/battery). New `rafOnScreen(target, frame, margin)` in
   `util.ts` runs a loop only while its element intersects the viewport (IntersectionObserver;
   pauses off-screen, resumes with an immediate frame). Wired to globe (hero), outro, and the
   hero encrypt loop. The journey loop self-schedules (3 reschedule points) so it got an inline
   gate — `if (!visible) return` + an observer that restarts it — **hardened** with an rAF-id
   guard (`schedule()` / `cancelAnimationFrame` on pause) so duplicate observer fires can't spawn
   parallel loops, plus a `resumed` flag that resets `lastRaw` on re-entry to avoid a
   stale-crossing false auto-send. Journey observer uses `rootMargin: 0` (heaviest loop — no
   preload bleed into the hero; `journeyTop ≈ hero height`, so any positive px margin would run
   the full cipher stream under the hero on taller viewports).
3. **Social/SEO meta** (`index.astro` head): `twitter:card=summary_large_image` + title / desc /
   image / image:alt, `og:image:alt`, `og:site_name`, `theme-color=#000000`, `<link rel=canonical>`.
4. **a11y:** wordmark `<span class="mark">` → `<button class="mark" type="button">` (now
   keyboard-reachable; still `location.reload()` on click; button reset added to `nav .mark`).
   Added `:focus-visible` ice-ring rules for nav mark/links, skip chevron, kb-done, enc Done,
   composer send, outro CTA.

### Verification (headless Chromium, then live)
- Build clean (JS 47.81 kB / gzip 16.62 kB), no console/page errors in either motion mode.
- Per-canvas `clearRect` frame counts by scroll zone PROVE the pause: hero → globe runs,
  journey/outro 0; mid-journey → journey runs, globe/outro 0; features → all 0; outro → outro
  only; re-entry → journey resumes (155 frames). Journey no longer runs under the hero (margin 0).
- Reduced-motion emulated: globe hero frames = 0 (static — but canvas painted, 733 non-blank
  samples), journey still tracks scroll (`p` follows), `.scroll-cue`/`.f-photon`/skip anim = `none`.
- Wordmark button reloads on click; `:focus-visible` outline present; tabIndex 0.
- Deployed via `deploy-landing.ps1` (preview server stopped first → `npm ci` clean, no EPERM).
- **LIVE + byte-verified:** JS `BmJLEC93`, CSS `BKkQ4cC7`. Live JS carries `IntersectionObserver`
  ×2 / `prefers-reduced-motion` ×4 / `rootMargin` ×2; live HTML carries `<button class="mark">`
  + all new meta; live CSS carries the reduced-motion block + `focus-visible` rules.
- **Committed + pushed** to `origin master`.

## Revision 8 — ship-readiness polish (single h1, caption contrast, sitemap)
Three of the five "ready to ship?" items done now; the 4th (Dependabot) is a separate later pass, the 5th (on-device eyeball) is the owner's.
- **Single `<h1>`.** The journey heading "Where does a message actually go?" was a 2nd `<h1>`
  (competing with the hero for the page title) → demoted to `<h2>`; CSS `.prompt h1` → `.prompt h2`.
  Page now has exactly one h1 (hero), rest h2/h3. JS only queries `.prompt` (container), unaffected.
- **Caption contrast (WCAG).** Faint text nudged up for legibility while keeping the moody dark
  look: `.scroll-cue` .35→.6, `.prompt p` .45→.62, `.outro .fine` .3→.55, `.f-row` .3→.55,
  `.f-honest` ice .45→.62. Verified by screenshot (outro fine-print + footer honest line now read
  clearly, aesthetic preserved).
- **Sitemap.** `public/sitemap.xml` → served at `/welcome/sitemap.xml` (200 text/xml), lists the
  canonical welcome URL. NOTE: a `robots.txt` was intentionally NOT added — at a `/welcome/`
  subpath it would sit at `/welcome/robots.txt`, which crawlers ignore (they only read the domain
  root `/robots.txt`, which is the PWA's territory). An effective robots + sitemap reference
  belongs at the domain root — a small root/nginx change, owner's call.
- LIVE + byte-verified: JS `BmJLEC93` (unchanged), CSS `D39osGPo`. Live HTML has one `<h1>`;
  live CSS shows `#eef6fb99`/`#eef6fb8c`/`#8fd8ff9e` (the bumped alphas) + `.prompt h2`. Sitemap 200.
  Committed + pushed to `origin master`.

### Still open (deliberately later)
- **Dependabot (7 alerts).** Grounded: `npm audit` → backend 0, scripts/smoke 0, **landing 2**
  (1 high = Astro ≤7.0.9 chained XSS, 1 low = esbuild dev-server file read on Windows). The other
  ~5 are almost certainly the **Flutter/frontend pub deps** (`pubspec.lock`, npm audit can't see).
  Correction to an earlier note: the landing DOES carry a high alert (not "main-app only") — BUT
  the landing deploys fully STATIC (astro `output: static`, nginx serves `dist/`), so the Astro
  advisories (dev-server / SSR / server-islands / error-page fetch / view-transitions /
  define:vars) don't run in prod → prod exposure ≈ 0. The Astro fix is a 5.18.2 → 7.1.3 jump (TWO
  majors, breaking). Verdict: hygiene, not an emergency; do in a dedicated pass (esp. the Flutter
  side, which needs the app test suite) or dismiss-with-rationale the static-neutralized ones.

## Revision 9 — Dependabot triage (the deferred item, done)
Enumerated the real alerts via `gh api` instead of guessing. Ground truth: **all 7 are in the
landing** (Astro ×6 + esbuild ×1) — ZERO Flutter/backend alerts (backend + scripts/smoke
`npm audit` = 0; the Flutter pub deps have no Dependabot alerts). Two corrections to earlier
notes: it was never "main-app deps only", and most fixes are a 5→6 bump (only the view-transition
one needs 7.1.0), not exclusively 5→7.
- **esbuild low — #83, dev-server arbitrary file read on Windows (GHSA-g7r4-m6w7-qqqr).** Astro
  pins esbuild `^0.27.3` so there's no in-range patch (fix is 0.28.1). Added a **scoped npm
  override** `overrides.astro.esbuild: "^0.28.1"` → esbuild 0.28.1 across the astro tree (vite
  deduped to it). Build clean and the emitted dist is **byte-identical** (JS `BmJLEC93` / CSS
  `D39osGPo` unchanged) — the fix is build-tooling only, so NO redeploy is needed; the alert
  auto-closes once master's updated lockfile is scanned.
- **6 Astro XSS/SSRF alerts — #81,82,84,85,86,87.** DISMISSED via `gh api` (`dismissed_reason:
  not_used`, per-alert rationale comment). Each targets an Astro *runtime* feature this **static**
  deploy never uses: prerendered-error-page SSR fetch (#85 high), unescaped slot name (#84 high),
  view transitions (#87 med), spread-attr names (#86 med), define:vars (#81 med), server islands
  (#82 low). Static prerender + nginx serving `dist/` means none of these code paths execute in
  production → prod exposure = 0. Deliberately did NOT run the Astro 5→6/7 major migration
  (breaking on a hand-tuned canvas site, zero prod payoff) — matches the recommended plan.
- **Frontend (Flutter): no action** — it has no alerts. (The earlier "the other ~5 are Flutter"
  hypothesis was wrong; corrected by the `gh` enumeration.)
- Net (confirmed via `gh`): **0 open** Dependabot alerts — 8 dismissed (`not_used`), 3 fixed
  (esbuild #83 + #87 + an older #70). Dependabot published a few more of the SAME
  static-unreachable Astro XSS class mid-pass (#88 view-transitions, #89 transition:* on hydrated
  islands, #90 spread-attr incomplete-fix) — dismissed with the same rationale.
- **Recurrence caveat:** because we deferred the Astro upgrade, new advisories for astro 5.18.2
  will keep appearing over time; each will be the same static-unreachable class (dismiss the same
  way). The DURABLE fix is upgrading Astro (5→6 clears most; 7.1.x clears the view-transition one)
  in a dedicated maintenance window with a full rebuild + browser smoke — worth doing eventually,
  not urgent given the static deploy neutralizes prod exposure.

## Revision 10 — skip chevron moved bottom-center → bottom-RIGHT (owner: users mis-tap it, skipping the whole tour)
The photon-pulse skip chevron sat dead-center at `bottom:12vh` (same height as the journey's own
"…on its way" hint), so it read as a central "continue/scroll" cue and got tapped — skipping the
entire tour. Moved to the bottom-right corner: `.skip-tour` `left:50%; transform:translateX(-50%)`
→ `right:6vw` (kept `bottom:12vh`, which clears the center progress rail + hint on desktop AND
mobile, where the rail is near-full-width).
- It now reads as a peripheral control, not part of the journey flow.
- Dropped the now-vestigial hint-coordination in `main.ts`: the `!hintShowing` carve-out (and the
  only `window.__journey` read in main) existed ONLY because skip shared the hint's center spot —
  irrelevant in the corner. Skip is now consistently visible through the journey. Refreshed the
  stale comment (it still described the old Rev-5 "round arrow bubble … where the hint lives").
- Verified (preview): skip renders bottom-right (~123px/119px from edges at 1280×800), shows
  during the journey, flips ↓→↑ in the last ~30% (aria "Skip the tour" / "Skip back to the
  start"), click still jumps to `#features` (scrollY 4112→7383), no collision with the center
  rail (screenshot).
- LIVE + byte-verified: JS `BFMsxPbf`, CSS `B5clvdmX` (`.skip-tour{…right:6vw;bottom:12vh…}`).
  Committed + pushed.

## Revision 11 — skip made FORWARD-ONLY (owner call: QA found the ↑ half overlapped the docked phone)
After Rev 10's bottom-right move, cross-width QA found the control's bidirectional half was a
problem: the `↑` "back to start" only shows in the high-scroll zone (`scrollY > 0.7·height`) —
exactly where the recipient device docks and fills the lower-right — so on iPhone the chevron
overlapped the docked phone (3–9px), and on narrow desktop the recipient's FLIGHT path crossed
the corner at raw≈0.72. `↑` and the docked phone structurally share that zone; no clean bottom
position holds both on a phone-sized screen. Presented the tradeoff; owner chose **forward-only**.
- `main.ts`: removed the up-zone (`upZone`, `.up` toggle, dynamic aria, the scroll-to-top click
  branch). Click always → `#features`. Skip shows only **mid-tour** (`raw 0.16 … 0.66`): past the
  composing/lifting sender (overlaps ≤~0.15 on mobile) and before the recipient emerges from the
  relay (~0.62) and flies through / docks in the lower-right (overlap onset raw≈0.72). Pure
  scroll bounds — did NOT rebuild the `__journey`/`hintShowing` coupling removed in Rev 10.
- `landing.css`: removed the now-dead `.skip-tour.up` rules. Position unchanged (`right:6vw;
  bottom:12vh`). The button's static `aria-label="Skip the tour"` is now always correct.
- Verified (preview, widths 375–1440 + iPhone 375/390/414): skip shows only ~0.16–0.66, hidden at
  both dock ends, **zero overlap with either phone anywhere it's shown**; click at raw 0.4 jumps
  to `#features` (scrollY→7384≈featTop). 
- LIVE + byte-verified: JS `C21qRj_x`, CSS `BRnDbUrD` (`.skip-tour{…right:6vw;bottom:12vh…}`, no
  `.skip-tour.up`; JS has no "Skip back"). Committed + pushed.

## Revision 12 — Done mobile-only + skip retargeted to the reply finale (bidirectional again, one fixed spot)
Owner asked for three things, images provided (image1 = the two-device "07 / Kate's turn" reply
finale; image2 = the features section).
- **Done button → mobile-only.** The hero terminal's `.enc-done` showed on desktop focus (no soft
  keyboard there → noise). Gated its `display:inline-flex` behind `@media (max-width:999px)`, so it
  only appears in mobile view. (`.kb-done` was already mobile-only via `body.kb-open`.)
- **↓ skip retargeted.** It scrolled OUT to `#features` (image2); now it scrolls to the two-device
  reply finale (image1) — `lenis.scrollTo(journey.offsetTop + (offsetHeight-innerHeight)*0.97)`
  (raw≈0.97 = caption 07, both devices docked). Verified: mid-tour click lands raw 0.97 / cap
  "07 / KATE'S TURN".
- **↑ restored, in ONE fixed spot.** The bottom-right chevron is bidirectional again: `↓` mid-tour
  (raw 0.16–0.66) → finale; at the finale (raw 0.955–1) it flips to `↑` "Back to the start"
  (`lenis.scrollTo(journey.offsetTop)`). Re-added the `.skip-tour.up` rotation CSS + dynamic aria.
- **The ↑ is DESKTOP-ONLY** (`@media (max-width:999px){ .skip-tour.up{display:none} }`): this is
  exactly the overlap that forced Rev 11's forward-only — at the mobile finale the docked device
  fills the lower-right and the device↔rail band is ~33px on a 667-tall phone (no room for the
  46px chevron). On desktop the finale centers both phones, leaving the corner 97px clear
  (verified 1245w, matching image1). Mobile users swipe up. `↓` still works on mobile (mid-tour,
  clear).
- Verified (preview): desktop ↓@0.4 → raw 0.97 "07 KATE'S TURN" → flips ↑ → click → raw 0 (start),
  up-arrow 97px clear of Kate. Mobile: Done `display:flex`, ↓ shows mid-tour, ↑ `display:none` at
  finale. LIVE + byte-verified: JS `TY8Ssk1P`, CSS `BJXz6M4T` (enc-done under max-width:999px;
  `.skip-tour.up{display:none}` mobile; JS has "Back to the start"/"Skip to the reply"). Committed + pushed.

## Revision 13 — skip arrows on BOTH ends, mobile included (owner reversed the desktop-only call)
Owner confirmed the ↑ lands them on the journey start (Bob's single device — image1 this round),
and asked for the ↓ to also appear there, on mobile too, so the two arrows bookend the same jump.
- **↓ now shows at the start.** Lowered its lower bound `raw 0.16 → 0.02`, so the ↓ "Skip to the
  reply" appears on the opening "WHERE DOES A MESSAGE ACTUALLY GO" / Bob screen (and through
  mid-tour). It jumps to the two-device reply finale — the same spot the mid-tour ↓ targets.
- **↑ now shows on mobile.** Removed the Rev-11/12 `@media(max-width:999px){.skip-tour.up{display:none}}`
  guard. So: ↓ at the start → finale; ↑ at the finale → start, on BOTH desktop and mobile — a
  symmetric start↔finale round-trip in the one fixed bottom-right spot.
- **Tradeoff (owner-accepted):** this is the mobile dock overlap we removed in Rev 11. It's clear
  at both TAP points (the start screen; the ↓'s finale landing at raw≈0.97), and only grazes the
  docked device's corner (~3–14px) if you scroll to the last ~2% (raw 0.98–1.0). Owner explicitly
  wanted the arrows there, so shipped as-is rather than re-hiding. (Considered a top-anchored ↑ to
  dodge it entirely, but that breaks the bottom-corner mental model from the images.)
- Done button stays mobile-only (unchanged).
- Verified (preview, 1280 + 390): ↓ shows at raw 0.05 both viewports; ↑ shows at raw 0.97 both
  viewports (mobile no longer hidden); ↓@start click → raw 0.97 "07 / KATE'S TURN", both phones,
  flips ↑. LIVE + byte-verified: JS `CN8bw2nn`, CSS `KqJS6kWo` (no `.skip-tour.up{display:none}`;
  enc-done still under `@media(max-width:999px)`). Committed + pushed.
## Revision 14 — Done pill hides on tap (owner: users re-tap it thinking nothing happened)
On iPhone, tapping the mobile `.kb-done` pill DOES dismiss the keyboard, but the pill visually
lingered, so users read it as dead and tapped again. Its visibility was driven purely by
`body.kb-open` (CSS): `releaseKb()` removes that class on click, which hides it in Chromium — but
on iOS the class-toggle → repaint can't keep up with the keyboard-dismiss reflow, so the pill
stays on screen a beat.
- **Fix (journey.ts):** hide the pill on the click itself, not just via `body.kb-open`. Click now
  does `kbDone.style.display='none'` then `releaseKb()?.blur()` — instant, repaint-independent
  visual feedback. `poseLifted()` clears the inline `display` (`kbDone.style.display=''`) whenever
  the pill is next lifted, so it re-appears normally on the next compose focus (CSS resumes control).
- No CSS change; `.enc-done` (hero terminal) left as-is — the owner's report was the upper compose pill.
- Verified (preview, 390×844 mobile): focus → pill `display:flex`; click → `body.kb-open` false
  AND inline `display:none` (hidden by both paths); re-focus after the 600ms suppress window →
  inline display cleared, pill `display:flex` again.
- First shipped on the Astro-5 build (JS `DQjQd-h8`). While pushing, `origin/master` had moved:
  a dependabot batch merged **Astro 5.18.2 → 7.1.0** in `/landing` (PR #88) plus sharp/backend
  bumps. Rebased onto it (only `LATEST.md` conflicted — kept the newer audit-session header, folded
  Rev 14 into its Previous list). Then **rebuilt from the rebased Astro-7 lockfile and redeployed**
  so prod == repo (the earlier deploy was Astro-5-built). Astro 7 is a 2-major jump on this
  hand-tuned canvas site — smoke-tested clean: zero console/page errors, all 3 canvases painting,
  single h1, compose lift + Done-pill hide + bidirectional skip (↓@0.05 "Skip to the reply",
  ↑@0.97 "Back to the start") all working.
- LIVE + byte-verified (Astro 7): JS `6oHf6wJ4`, CSS `DJ-65XJU`. Live JS carries
  ``q.addEventListener(`click`,()=>{q.style.display=`none`,K()?.blur()})`` and the poseLifted
  ``q.style.display=```` restore; live HTML references both new hashes. Committed + pushed.
