# 2026-07-27 — nav travel motion + the lock and the globe wear the cell

**Branch `feat/nav-rework`, still UNMERGED, still 0.0.129.** Live ephemeral branch
deploy is **`bc40116`**, smoke 5/5. Backend untouched at 0.0.127/`3861166`.
Three owner approvals this session; the release is still gated on his explicit
"merge" and he has NOT given it.

## What was done

### 1. Tab-to-tab travel got two more beats (owner: "ok thats nice im pleased with that result well done")

The previous round shipped a glass lens that glides between tabs. Every
animation layer fired on the SAME frame — nothing staggered, nothing
direction-aware, nothing distance-aware. That symmetry was the remaining
headroom. Two changes, presented to him as a menu of six and picked by
recommendation:

- **Lens stretch.** The pool elongates toward the destination and flattens as
  it goes, widest at the midpoint, volume roughly conserved so it reads as
  liquid rather than a box being resized. Scales with the distance travelled,
  so a two-slot jump throws twice as far.
- **Delivery stagger.** The tab you tap stays dark for 160ms and lights up only
  once the lens is 59% of the way there (`easeInOutCubic(160/300)`). The lens
  DELIVERS the selection instead of racing it.

The lens is explicitly driven now (`_ActiveLens`), not an `AnimatedAlign`: the
stretch has to know how far THROUGH the journey it is and an implicit animation
only exposes its endpoints. Retargeting mid-flight restarts from wherever the
lens actually is.

Icon and label now ride ONE animation. Separate timers were invisible while
both started on the tap, but would have read as the label answering before the
mark it belongs to.

**`Alignment` places a child by its EDGES**, so the same alignment lands a wider
child's centre closer to the middle of the pill — the lens would sag inward
exactly as it stretches. `_alignmentFor` solves for the CENTRE instead.

### 2. A reduce-motion bug caught in review, not by the owner

`_ActiveLens.didUpdateWidget` returned on an unchanged index BEFORE it checked
`reduceMotion` — and switching reduce-motion on arrives as exactly that: a
rebuild with the same index. The stretch died on its own (`build` zeroes
`flight`) but the glide carried on to the end of its 300ms, against the
instant-motion contract. `_NavItem` already ordered those two checks correctly;
the lens now matches it. Falsified: lens frozen at 189px where the test demands
636px.

### 3. `password` and `language` now wear the cell (owner: "rest is ok well done")

Owner: the reset-password icon "doesnt really fit the rest hex theme", and
later, unprompted: "langugage icone is not hex too … maybe just make a hex
instead of round globe".

Diagnosis worth keeping: every other mark in the console says **the hex cell is
your node, and each mark does something to it** — `keys` is the node with a
keyhole cut in it, `logout` the node detaching along a trace, `deleteNode` the
node struck out. The padlock was the only **physical object** in the set, and it
needed an optical nudge to sit on the grid at all. The globe was the only round
shell.

Three directions were rendered for password (shackle-on-a-cell / masked cell /
re-issued cell) and the owner picked **A, shackle on a cell**, plus **A, hex
globe** — then said **"perfect them"**, which is what licensed the second round.

- **password** — body IS a cell, with a **true U** shackle: two legs rooted in
  the body's upper edges and a half hoop above them. A pointy-top hex fights a
  shackle because its top point rises into the opening; the two constructions
  that hung an arc straight off the body read as a handbag and an avocado. The
  optical nudge stays — the imbalance it corrects (thin open line-work over a
  wider closed form) survived the redraw.
- **language** — shell is a cell, meridian and equator pulled deliberately OFF
  it: 1.6 clearance at the poles, 0.93 at the flats. Straight-swapping circle
  for hex kept the old 7.6/15.2 oval and crowded to 0.8 and 0.33. **Three 1.8
  strokes inside a 16-unit hex is what makes a mark choke at 24px, and
  clearance is the only cure.**

### 4. Dependabot #95 triaged (first time; it had fired on every push for days)

`brace-expansion <= 5.0.7` DoS, high, `backend/package-lock.json`. **Every copy
in the tree is `dev: true`** — it arrives only through eslint / jest / nest-cli.
The container ships compiled JS with prod deps only, so an OOM in a glob
expander cannot be reached by a request. Not deploy-blocking, not
release-blocking. NOT fixed: it lands on master, which needs his word.

## Verification

- **879 passed / 4 skipped** (was 876), `flutter analyze --no-fatal-infos lib/ test/`
  → 0 issues. Backend untouched at 536.
- Three deploys this session (`6a8aa4d`, `9ebcd21`, `bc40116`), smoke **5/5** each.
- Tests added, **each falsified**: the delivery wait (red at `0.599` where it
  demands `0`), the stretch width, the squash height, the mid-flight
  reduce-motion snap.
- **One test was written and DELETED**: it claimed to defend the centre-sag
  correction and still passed with the correction reverted. The sag is ~10px on
  a 104px slot, inside a single frame of travel, so nothing assertable
  separated correct from broken without also failing on correct code. The
  correction stays, documented as untested rather than shipped under a green
  test that proves nothing. **A test that cannot fail is worse than no test.**
- Glyph candidates were **temporary enum members drawn by the REAL painter**,
  not a duplicated preview painter that could have diverged on scaling, caps or
  centring. Side benefit: the keyline test measured all six candidates
  automatically. All members, cases and the throwaway sheet are deleted.

## Notes for next session

- **Still UNMERGED, still 0.0.129.** On his explicit "merge": bump to **0.0.130**
  as the LAST branch commit → `gh pr create` + merge (**no PR exists**) →
  `deploy-web.ps1` from master → `post-deploy-smoke.mjs`.
- **`appearance` is explicitly OFF the table** — owner, this session: "appearance
  leave as it was". It is untouched on this branch (0 references in the diff).
  The long-standing fork (its glyph renders nowhere because the live
  `AppearancePreview` owns that row's leading slot) is now a decision, not an
  open question: leave it.
- **Five marks are still non-hex objects** — `devices`, `webStorage`, `media`,
  `metadata`, `cache`. Flagged to him; he said "rest is ok". Do not
  re-litigate unless he raises it.
- Dials if he revisits: `kDrawOnStart` 0.4 (the 160ms wait — the one thing only
  his phone could judge), `kLensStretch` 0.4, `kLensSquash` 7, and for the lock,
  `_arc(Offset(12, 9.2), 2.6, …)` — raising 9.2 or growing 2.6 opens the hole.
- **He can miscommunicate and self-correct.** This session he answered a long
  technical report with "what did you just implement i cant tell?" — the answer
  was that the report buried the two-sentence answer under diagnostics. Lead
  with what changed in plain words; keep the evidence below it.
