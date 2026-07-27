# Console glyph system + the three Settings sub-screens

**Date:** 2026-07-25 — owner rejected the hand-drawn Settings glyphs (*"icones in
settings are bad desing too user some frontend skills impress me"*) and asked for the
Settings SUB-screens in the same breath. Both shipped to the branch. Live ephemeral
deploy is **0.0.128 / `85a04dc`**, smoke 5/5. Still NOT merged, no version bump —
master untouched at `5a757d3`, PR #97 still open.

## What was done

1. **Audited why the old set was bad, before redrawing anything.** Two separate
   failures, and only naming both prevented shipping a tidier version of the same
   mistake:
   - **Concept:** eight of the nine glyphs were Material icons redrawn by hand —
     `shield+check` is `Icons.verified_user`, the laptop is `Icons.laptop`, the slashed
     circle is `Icons.block`, plus `key`/`logout`/`language`/`wifi`. Hand-drawing clip
     art does not stop it being clip art; it only loses Material's optical tuning.
   - **Craft:** there was no keyline grid. Three circles at three diameters (8, 7.8,
     7.6). `signal` anchored at y=17.4 in a 24-unit box, so its whole mass sat in the
     bottom half. `key` spanned y 8.6→15.2 while `shield` spanned 3.4→20.6 — wildly
     unequal mass on one row rail.

2. **`lib/widgets/console_glyphs.dart` (new).** One 24-unit design space that EQUALS
   the render size (scale factor exactly 1, no fractional-pixel coordinates), one
   canonical circle / square / pointy-top hexagon, one stroke weight (1.8), one
   terminal radius. Glyph box 22 → **24px** inside the 44px terminal; 22 was quietly
   small for its frame. Geometry is emitted as DATA (`ConsoleGlyphGeometry` = strokes /
   fills / dots) instead of painted inline, specifically so the grid is measurable.
   Resolved geometry is memoised per glyph.

3. **A real bug fell out of the measurement.** `Path.getBounds()` is deliberately
   CONSERVATIVE — for an arc or a rotated oval it bounds the Bézier control points, not
   the curve, over-reporting by ~20% here. `centred()` divides by that rectangle, so
   **every arc-based glyph was mis-centred** (`push`, `privacy`, `quantum`, the
   padlock). Bounds now walk the contours via `computeMetrics()` at 48 samples. The
   keyline test caught this, not the eye.

4. **Two complete sets drawn, rendered, and put in front of the owner** — the workflow
   that worked for the console itself. `instrument` kept the conventional silhouette on
   a proper grid; `schematic` drew a wiring diagram of what each row does to your node,
   but only for the 9 rows where that is literally true (the other 6 fell through on
   purpose — a node diagram for "downloaded audio cache" is a puzzle, not an icon).

5. **Owner picked per-row**, and the set collapsed to one drawing per glyph:
   node diagrams for `language`, `privacy`, `blocked`, `devices`, `push`, `deleteNode`,
   `logout`, `keys`; the conventional server stack for `metadata` (his call — the row is
   about the machine that holds the data); and **`appearance` as a half-filled HEXAGON**,
   his amendment — the local node is the app's only circle, so a contrast disc on that
   row would have claimed a meaning it does not have. `ConsoleGlyphSet`, the `set`
   parameter on `SettingsConsoleRow`/`ConsoleHexIcon`, and the two-column sheet were all
   deleted with the losing set.

6. **Two glyphs redrawn mid-review after judging my own render.** `blocked` was a
   schematic open circuit — a 1.8-unit gap with cap strokes — which at the shipping size
   is under two pixels, so it read as two nodes **JOINED**, the opposite of the word on
   the row. Now node pair + trace + the universal slash: a legibility failure does not
   get fixed with a second subtle idea. `devices` was node-plus-one-terminal and read as
   a balloon on a string; now a **chip with a pin-out**, which is the most literal
   possible take on the owner's "inside a computer" rationale.

7. **Three sub-screens converted** (three parallel subagents, disjoint files, one
   integration pass by the main agent):
   - `privacy_safety_screen.dart` — the worst offender. A 64px `Icons.verified_user`
     and six translucent Material cards became a `ConsoleHexIcon(height: 68)` header and
     `ConsoleInfoRow`s under section captions. The translucency was independently a
     `SPEC.md` §1 violation (never glass behind body text). **The long-press hacker-mode
     unlock survived on the new header** — it was called out as load-bearing in the brief.
   - `blocked_users_screen.dart` — `AvatarCircle` → `HexAvatar` on the shared 12px axis
     (row-parity rule), `ListView.separated` → `.builder` with dividers gone, unblock
     restyled as a bordered console chip with a per-user semantics label.
   - `appearance_screen.dart` — adopts the shared `SettingsSectionCaption` (deleting its
     local duplicate, which was the widget the shared one was copied FROM), hex selection
     marks instead of Material check/radio.

8. **Caption casing bug, caught in my own render.** Two Privacy captions reuse screen
   TITLES (`Privacy & Safety`, `Your identity fingerprint`) next to captions from
   already-caps section keys, putting `SECURITY / Privacy & Safety / PREFERENCES` on one
   rail. Fixed by upper-casing inside `SettingsSectionCaption` so **no call site can
   reintroduce it**, rather than patching the two callers.

9. **The Appearance row's theme preview, fixed on both axes** (owner caught each in
   turn). `_AppearancePreviewScene` positions everything at ABSOLUTE insets and scales
   only bubble WIDTH, so the two axes need opposite treatment:
   - *Width.* The miniature was drawn at 92 and centre-cropped to the 38px hex purely
     to push its radius-12 border outside the clip — but the hex shows only the middle
     38 of those 92, and both bubbles live at `left: 8` / `right: 8`. The crop was
     deleting exactly the strips carrying the theme's colours: *"most of the hex is on
     background color with little visible chat bubble"*. `AppearancePreview` gained
     `showBorder` (default true, so the Appearance cards are untouched); with no border
     there is no reason to oversize, and it renders at the terminal's own width whole.
   - *Height.* Shrinking it to the terminal's 44 slid the composer bar
     (`bottom: 6`, height 7) up to y 31–38, through the "mine" bubble at y 25–36 — and
     the bar paints AFTER it in the `Stack`, so it covered it: *"green/blue bubble is
     covered by bottom block"*. The miniature now stays above the collision height and
     overflows, with the alignment DERIVED so the two bubbles' midpoint lands on the hex
     centre and the composer falls past the bottom vertex instead of being sliced.
   The scene's insets are now exported constants and are the single source of truth for
   the widget, the alignment arithmetic and the test. **Hardcoding them is precisely
   what let the bar slide back over the bubble**, so do not re-inline them.

10. **The chat background was then cut from that hex entirely** (owner: *"background in
    appearance hex is not really needed"*). The row's subtitle already names it and at
    38px the pattern was texture, not information. It also dissolved a defect the Spec
    review caught: the `glyphs` layer renders its scene at 2x and `FittedBox`es it back
    down, halving every ABSOLUTE offset, so on Hieroglyphs both bubbles came out
    half-height and sat in the upper third — a partial return of the original complaint.
    **Bubble height is absolute, so no resize could have restored it on that layer**;
    pinning the hex to `ChatBackgroundLayer.plain` keeps the miniature on ONE geometry.
    A test asserts it, and `_host` now seeds `themePreference: 'cosmic'` precisely so the
    assertion CAN fail — cosmic is the only preference resolving to a non-plain layer.
    Falsified: *"Expected: ChatBackgroundLayer.plain / Actual: ChatBackgroundLayer.starfield"*.

11. **Two-axis review** (`code-review` skill, fixed point `39275f4`, both axes in
    parallel). **Standards: 0 hard violations**, 4 judgement calls (P3) — it independently
    confirmed zero `Color(0x...)`, no new hardcoded English, no motion in banned zones,
    and noted the diff IMPROVES `SPEC.md` §1 compliance by de-translucent-ing Privacy.
    **Spec: 0 missing, 0 scope creep, 1 P2** (the Hieroglyphs bug, closed by item 10).
    Taken: the P2, plus a stray `SizedBox(height: 8)` after `appearance_screen`'s second
    section caption but not its first. **Declined on purpose** (root `CLAUDE.md` §1,
    recorded in `85a04dc`): extracting the repeated console-rail `EdgeInsets`, sharing the
    hex-hairline painter recipe across three sites, and bundling the `kPreview*` constants
    into a value type — all unasked-for refactors that reopen review surface.

12. **A harness knob that proved nothing, and was reverted.** `?bg=glyphs` was added to
    `glass_preview` to review the non-default background; both panels rendered identical
    starfield because `SettingsScreen.initState` calls `loadChatBackground(userId)` and
    clobbers the seeded value. Reverted rather than left as a switch that silently does
    nothing. If this is ever needed: seed after the load settles and ASSERT
    `resolvedChatBackground` before trusting the render.

## Key files

- `frontend/lib/widgets/console_glyphs.dart` (new, ~470 lines) — keyline constants,
  `ConsoleGlyph` (15), `ConsoleGlyphGeometry`, `consoleGlyphGeometry()`,
  `ConsoleGlyphPainter`.
- `frontend/lib/widgets/settings_console.dart` — re-exports `ConsoleGlyph`; gained
  `ConsoleInfoRow` and `ConsoleHexIcon.height`; caption now upper-cases.
- `frontend/lib/screens/{privacy_safety,blocked_users,appearance,settings}_screen.dart`
- `frontend/test/widgets/console_glyph_keyline_test.dart` (new)
- `frontend/test/preview/console_glyph_sheet.dart` (new) — single-set reference sheet,
  ends in a true-size strip.
- `frontend/test/preview/glass_preview.dart` — gained `?screen=settings|appearance`, so
  ONE harness renders all four Settings screens (it already provides Encryption/Friends,
  which `settings_preview.dart` does not).
- `docs/design/settings-console/glyph-set-final-{cosmic,light}.jpg`,
  `subscreens-{cosmic,light}.jpg`

## Verification

- `flutter analyze --no-fatal-infos lib/ test/` → **0 issues**. Full suite **845 passed
  / 4 skips** (was 826; the keyline test adds 17, and the earlier 33 collapsed to 15
  when the A/B set went away). Backend untouched at 536.
- **Both new tests falsified.** Disabling `centred()` → 3 red. Dropping `toUpperCase()`
  → `Expected: exactly one matching candidate / Actual: Found 0 widgets with text
  "PRIVACY & SAFETY"`. Both restored and re-verified green.
- The keyline test measures all 15 glyphs for centring (±0.5), keyline extent
  (≤8.2 + 0.25) and minimum mass, and asserts `appearance` is a hexagon by its
  width/height ratio (0.866) — a disc would be square in its bounds.
- Rendered cosmic + light at every step; all four Settings screens captured via
  `glass_preview.dart`. Deploys: `7ff932c` (instrument set), `b23935d` (final set), then **`85a04dc`** (the
  Appearance-preview fix), smoke **5/5** each, `main.dart.js` literally contains `85a04dc`.
- `dart format` on touched files ONLY. `main_shell.dart` still byte-identical to master.

## Notes for next session

- **Live is `85a04dc`, 0.0.128, branch-only.** PR #97 open, 46 commits ahead of master
  `5a757d3`. The release remains gated on an explicit owner "merge": bump
  `frontend/pubspec.yaml` 0.0.128 → **0.0.129** as the LAST commit on the branch, merge
  #97, `deploy-web.ps1` from master, `post-deploy-smoke.mjs`.
- **`push` is the one glyph the owner never named.** He listed every other row; the
  pattern said node-diagram so it got one, and he was told explicitly. If he comes back
  on it, that is the row.
- **OPEN: the `appearance` glyph renders NOWHERE in the app, by construction.** The
  owner asked for it as a hexagon and it is drawn and tested — but
  ``_appearancePreviewInHex`` passes `leadingOverride: _appearancePreviewInHex(settings)`
  on that row, which replaces the glyph with the live `AppearancePreview` miniature, and
  the Appearance sub-screen has no header mark. So the only place the hexagon is visible
  is the reference sheet. **Verify this in source before telling him it shipped.**
  A 68px `ConsoleHexIcon` header WAS tried on the Appearance sub-screen and reverted:
  it pushed the background cards 76px down, which broke
  `appearance_screen_test.dart` ("theme default follows Cosmic…") because the tapped
  card lands under the glass top bar — and more importantly it was never asked for, and
  Appearance is the one screen whose content already IS visual previews, so a decorative
  mark there costs first-fold space for nothing. The real fork, which only the owner can
  settle: either the glyph REPLACES the live preview on the root row (undoing an
  approved decision — the miniature is the better identifier at 44px), or the row keeps
  the preview and the hexagon stays a sheet-only mark. Do not guess this.
- **Renders are ~1.6× the physical size of his phone** (390 logical px ≈ 103mm on a
  desktop monitor vs ≈65mm in the hand). That gap is what killed the bus. Renders pick a
  DIRECTION; the device gives the verdict. Both new glyph decisions above were made from
  a render and still need his hand.
- Harness trap worth keeping: `hub` `op:"start"` cannot spawn `flutter` on Windows —
  it is a batch file. Use `application: "cmd.exe"`, `args: ["/c", "C:\\flutter\\flutter\\bin\\flutter.bat", ...]`.
- Screenshot readiness: do NOT poll for byte-size stability, webp compression jitters
  and the loop never converges. `networkidle2` + a fixed 6–7s settle after the bundle is
  already compiled is what worked.
- Still queued, none promised: the `ListView` rewrite of the honeycomb for >200 contacts
  (deliberately deferred — 22 layout tests + breaks focus traversal), "sent invites as
  ghosts" (needs a backend change to `friends.service.ts getPendingRequests`), Chats `+`
  as a honeycomb picker.
