# Bottom nav rework — glyphs, selected state, tab-switch travel

**Date:** 2026-07-26

**Status: every design question is SETTLED and owner-approved. The branch is
`feat/nav-rework`, UNMERGED, live as ephemeral branch deploy `2d48f7a` / 0.0.129.**
Master is untouched at 0.0.129 / `9d24d7b`. Nothing is pending except his explicit
instruction to merge.

## What was done

1. **Diagnosed the existing nav.** Stock Material icons (`chat_bubble_outline`,
   `people_outline`, `settings_outlined`) — the last surface still speaking the language
   the Settings console purged. "Animation" was an instant capsule swap plus a Material
   ripple, i.e. none.
2. **Round 1 glyph set REJECTED** ("all are kinda bad"). Honest cause, worth keeping: all
   three marks were small hex clusters, so they differed only in DETAIL. Nav glyphs are
   the most-glanced marks in the app and must differ in GROSS SILHOUETTE.
3. **Round 2+3 A/B, owner picked per row:**
   - `chats` — hex speech bubble ("its just wow"). Replaced two nodes joined by a
     hairline, which at 24px was `blocked` minus its slash.
   - `contacts` — C1, three cells sharing edges on the honeycomb pitch. Chosen over a
     4-cell diamond and a 7-cell flower.
   - `settings` — G3, a gear wearing the cell, teeth on the hex's POINTS. Owner
     direction: "just dress it up in a cube". Replaced a circle-with-cardinal-ticks that
     read as a gunsight. `ConsoleGlyph.localNode` renamed to `.settings`.
   - `language` (Settings console, he called the old one bad) — the meridian globe. Two
     node-diagram alternatives were drawn and killed at true size: a bowtie and a pair of
     scissors.
4. **Selection indicator: built, then DELETED.** A travelling accent bar under the row was
   mis-positioned into the middle of the pill by a greedy `Center` inside an
   `AnimatedAlign`, so it cut straight under the glyph on every active tab. Owner: "it
   cover it delete it". Removed outright rather than relocated.
5. **Animation, three attempts:**
   - *Scale pulse* (1.0→0.92→1.06→1.0) — "pulse is not it ... too little animation".
   - *Draw-on* via `PathMetric.extractPath`, the trim the contact board already uses.
     Researched first: Telegram's tab icons are per-icon authored Lottie/TGS files
     (core.telegram.org/stickers), and Flutter's `AnimatedIcon` only covers its own
     built-in Material set. Result on device: "only gear is moving, rest is static" — a
     stroke reveal at 24px reads as a plain colour change; only the gear's rotation
     looked like motion, and he called that rotation bad design.
   - *Outline → filled*, which is what every platform actually ships (Material 3 "the
     icon becomes filled", iOS outline/filled SF Symbol pairs, Android's two-state
     `AnimatedVectorDrawable`). The change is MASS, which survives 24px.
6. **Flush fills rejected on device: "chat icone is all black".** A closed silhouette
   filled to its own outline is one black hexagon at 24px, and worse on light themes
   where the accent is nearly black.
7. **The settled selected state, owner-approved ("yup thast good").** His direction after
   the rejection was *"chats icon can be filled in but no all one color inside icone make
   it same as others filled inside but with other lines"*, so the pattern is now uniform:
   an INSET fill sitting inside outlines that stay visible.
   - `chats` — inner cell inset to r 5.2, with **two message lines knocked out of the
     fill**. The inset alone only produced a ring; the lines are what keep the filled
     state reading as a chat bubble. They sit inside the hex's full-width band
     (y 8.0–13.2) so neither clips a sloping edge.
   - `contacts` — three cells inset to r 3.2, flooding in sequence.
   - `settings` — the only glyph with no fill: its teeth are thin spokes rooted inside
     the body, so any fill swallows their roots. States selection by STROKE WEIGHT
     (1.8 → 2.5) instead. Neither filled glyph thickens its stroke — that would close the
     narrow gap that makes the inset read as inset.
8. **A render caught a fill defect before he did:** filling the comb's three shared-edge
   cells flush merges them into one shapeless lump. The inset exists for that reason, and
   the comb's stroke deliberately does NOT thicken — widening it would eat the ~2.4-unit
   gap holding the filled cells apart.
9. **Attribution corrected.** His "gears on is ... all black" was corrected a message
   later to the chat icon; comments and a test had begun recording TWO device rejections
   where there was one. The gear is on weight by my render judgement, not his verdict —
   one line restores its fill if he disagrees.
10. **Per-glyph motion, APPROVED** ("yes thats it nice thats good"). Each mark moves in a
    way only it could: the comb's cells fly straight out from the glyph centre and
    reassemble, the bubble lifts and settles, the gear turns one tooth pitch. All
    TRANSIENT — `_bump()` is exactly zero at both ends, so resting and selected drawings
    stay identical and nothing is left displaced. The gear's 60° is one tooth pitch on a
    6-fold mark; **the owner suggested 45° and my objection to it was WRONG** — since the
    rotation settles back to zero, 45° would not have rested crooked either. It was a
    taste call stated as a constraint, and the comment now says so.
11. **Tab-to-tab travel took three attempts, and the pattern in the rejections is the
    single most useful thing in this file.** A hex socket framing the active tab:
    *"looks messy, outer line is too small for nav icone"*. A travelling node on a
    dormant rail: *"its mid i dont like it"*. Both — and the accent bar before them —
    were SMALL HARD-EDGED elements competing with the glyphs. What landed was the
    opposite: **a glass lens**, an edgeless pool of `GlassTheme.activeCapsule` that
    glides under the selected tab (300ms easeInOutCubic, sweeping THROUGH a skipped
    slot). Owner: *"yup thats it"*. `activeCapsule` is the token the spec already
    defines for this and it had been unused since the console rework stripped the
    Material capsule, so every theme brings its own tuned tint.
12. **Two bugs caught before the lens shipped.** It had only a `height` inside a
    `Center`, so it collapsed to ZERO WIDTH and rendered nothing. And its sweep test
    asserted a 6px window around the skipped slot, which a ~50px-per-frame sweep jumps
    clean over — it would have failed a perfectly good animation. The test now asserts
    samples landing on BOTH sides of that slot, which no sampling rate can miss.

## Key files

- `frontend/lib/widgets/console_glyphs.dart` — `kGlyphStrokeActive`, `_activeStroke`,
  `ConsoleGlyphGeometry.activeFills`, `_regionProgress`, painter `progress`/`activeColor`,
  the four redrawn glyphs, `_radial`/`_hexVertexAngles`.
- `frontend/lib/widgets/icon_selection.dart` (new) — the decoupling seam. The nav publishes
  progress + active colour and still takes plain `Widget` icons; `ConsoleGlyphIcon`
  consumes it; a plain `Icon` ignores it.
- `frontend/lib/widgets/glass/glass_bottom_nav.dart` — `_NavItem`, entrance/exit
  controllers (340ms in, 200ms out), `kTravelDuration`/`kLensHeight`/`activeLensKey`,
  ripple suppressed.
- `frontend/lib/screens/main_shell.dart` — nav destinations; the bespoke chat-bubble
  painter that existed only for the old Material icon is deleted (−100 lines).
- `frontend/test/widgets/glass/glass_bottom_nav_test.dart`,
  `frontend/test/widgets/console_glyph_keyline_test.dart`.

## Verification

- `flutter analyze --no-fatal-infos lib/ test/` → 0 issues. Full suite **876 passed / 4
  skips**. Backend untouched at 536.
- Deploys, all EPHEMERAL branch builds at 0.0.129 (branch deploys never bump semver),
  smoke **5/5** each: `0ba31c2` → `32811a9` → `ede43d8` → `f2e5b76` → `da3847b` →
  `25e5cc3` → `313abdd` → `8b6ab2e` → `fafa904` → **`2d48f7a` (live)**.
- Every behavioural test falsified: entrance runs / outgoing retracts rather than snaps /
  reduce-motion skips both halves / comb seams survive (red against flush fills) / both
  of the bubble's knockout bars (deleted in turn) / the lens sweep (red against a
  zero-duration travel).
- The 24px seam clearance is 0.31 design units, so it is held by a GEOMETRY test, not a
  pixel assertion — antialiasing would smear it either way.

## Notes for next session

- **Design is settled and approved end to end. The only thing left is the release**, and
  it is gated on his explicit "merge": bump `frontend/pubspec.yaml` 0.0.129 → **0.0.130**
  as the LAST branch commit, open and merge a PR, deploy master, smoke.
- **Do NOT resurrect the travelling node or the hex socket.** Both were built, rendered,
  deployed and rejected. The rule they taught: on this pill, small hard-edged markers
  lose to edgeless light. The accent bar before them died the same way.
- **`main_shell.dart` is intentionally no longer byte-identical to master** — the nav
  destinations live there. That old hard rule does not survive this branch.
- **Renders keep flattering things his hand rejects** — several treatments passed a
  render this session and failed on device. Render to pick a DIRECTION, deploy to get a
  verdict.
- Dials if he revisits: lens height (50) and falloff stops, `kGlyphStrokeActive` (2.5),
  `_kCellSpread` (2.2) and `_kBubbleLift` (1.6). Beyond what paths can express, the next
  real step is a Rive/Lottie dependency with an authored file per icon.
- Unresolved from the merged branch, untouched here: the `appearance` glyph renders
  nowhere, and `push` is the one glyph he never named.
- Desktop JPEGs from this round: `fireplace-nav-b.jpg`, `fireplace-nav-ab.jpg`,
  `fireplace-nav-round2.jpg`, `fireplace-nav-gear.jpg`, `fireplace-language.jpg`,
  `fireplace-nav-fill.jpg`, `fireplace-nav-states.jpg`, `fireplace-nav-motion.jpg`,
  `fireplace-nav-socket.jpg`, `fireplace-nav-node.jpg`, `fireplace-nav-lens.jpg`.
