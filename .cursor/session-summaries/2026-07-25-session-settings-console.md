# Settings "local node console" + the local node bus, and an avatar-gate hole

Branch `feat/contact-network`, continuing the contact-network visual pass. Eleven commits
today, `773e0dd` → `ef59dc4`. Two ephemeral branch deploys, both **0.0.128** (branch test
deploys never bump semver). Master untouched at `5a757d3`. PR #97 still open, not merged.

## Commits (today only)

| sha | what |
|---|---|
| `773e0dd` | docs: LATEST refresh for the wiring/scale round |
| `bccd3d1` | **fix**: a changed contact set no longer defeats the avatar gate |
| `837e81c` | docs: retire the refuted viewport theory |
| `956479e` | **feat**: rebuild Settings as the local node console (variant A) |
| `a342640` | docs: record the console — **deployed** |
| `aa14ad5`, `86c2d87` | docs: deploy record, then de-rot its wording |
| `d27c315` | docs(design): variant B re-rendered on the shipped console |
| `2b646c1` | **feat**: wire the console to the local node bus (variant B) |
| `18c97a9` | **test**: pin that only the destructive row lights the bus — **deployed** |
| `ef59dc4` | docs: record the bus deploy |

## 1. Pickup — the handoff verified clean, with one gap

Everything the handoff claimed checked out against the repo: branch tip, live deploy,
`main_shell.dart` byte-identical to master, every named symbol present, **821 passed / 4 skips**
re-run from scratch. The one gap was `LATEST.md`, which had stopped at `d18f938` — it still
said 819 tests and "awaiting device pass on `9d968c7`", with nothing about the wiring, either
perf fix, or the scale numbers. Refreshed in `773e0dd`; the wiring/scale round also got its own
dated file, `2026-07-24-session-contacts-wiring-and-scale.md`.

## 2. Lazy-avatar review — one real bug, two things REFUTED

A `reviewer` subagent went at the `30e6b03` gate; every finding was then verified against source
by hand before acting.

**REAL (P2), fixed in `bccd3d1`.** `_armedThroughRow` is a high-water mark that was never reset.
One scroll to the bottom pins it at the last row **for the rest of the session**; every later
rebuild with a different contact list then arms ALL N avatars at once while the user sits back at
row 0. The search field triggers it exactly: scroll down → filter → clear → 60 of 60 fetch. One
scroll silently disabled the optimisation that had just shipped.

Fix: `didUpdateWidget` zeroes the mark when the contact run changes, compared **by `id`** —
`UserModel` has no `==`, so comparing instances would reset on every provider tick that hands
back freshly-built objects for the same people. `_armedFloor` deliberately gets NO reset: the
build immediately behind `didUpdateWidget` recomputes it from the current viewport
unconditionally, so resetting it would be dead code.

*Falsified:* disabling the reset turns the new filter-cycle test red with
`Expected: less than <60>, Actual: <60>`.

**REFUTED #1 — the owner-facing "stuck initials" theory.** The previous handoff told the owner
that a hex stuck on initials meant `_visibleThroughRow` viewport math. That is impossible. The
formula arms `ceil((offset + viewport + rowPitch − 140) / rowPitch)` while the last on-screen row
is `floor((offset + viewport − 110) / rowPitch)`; the difference forces ≥1 row of slack for every
offset, viewport and pitch — it over-arms, never under. And the arming viewport and the layout
viewport are the SAME `safeRect.height`, so safe-area or keyboard insets shrink both identically
and cannot desync. The claim was removed from `LATEST.md` in `837e81c` with an explicit
do-not-repeat note.

**REFUTED #2 — by experiment, and the fix was thrown away.** The reviewer also claimed a viewport
shrink could un-arm already-visible faces, because "before the first scroll the mark is 0". A fix
and a test were built; breaking the code to falsify the test left it **GREEN** (`tall=28,
short=28`). The premise is false: the scroll controller notifies on mount, so the mark is already
populated before any user scroll. Both the fix and the test were deleted rather than ship
defensive code for an unreproducible defect and a test that cannot go red.

## 3. Settings → the "local node console" (`956479e`)

Owner: *"settings tab looks like a diffrent app... local node is round not hex i would leave that
that mean avatar in settings stays round but rest is for rework"*.

What was actually wrong, from the old `settings_screen.dart`: a tinted `GlassSurface` card per
row (which also violated playbook §1 — glass is floating chrome, not scrolling content), stock
`Icons.*` with a chevron on all 8 rows, four different corner radii (16 / 20 / 8 / circle), two
hardcoded `Colors.white`, and 8 flat tiles followed by 4 loose `Padding`s.

Three variants were prototyped on the real chrome and rendered: **current** (baseline),
**A** (console), **B** (A + spine). Owner picked A.

Shipped:

- **`LocalNodeCore`** extracted out of `contact_network_view.dart`'s private
  `_LocalReticlePainter` into `lib/widgets/local_node_core.dart`, consumed by BOTH tabs. The
  Contacts core and the Settings header are now literally the same widget because they are the
  same entity — you. It stays a CIRCLE among hexes on purpose; that shape difference is what
  marks the local node. Tick LENGTH now scales with the rim (`(r*0.12).clamp(4,9)`), which at the
  board's `r=34` reproduces the existing 4px tick to within 0.08px.
- **`lib/widgets/settings_console.dart`**: opaque rows, no dividers, no chevrons, 44px hex at
  left offset 12 / 12px gap — the exact geometry Chats and the Contacts classic list already use.
- **Drawn glyphs, not Material** (owner: *"dont forget to also change whats inside those hexes"*).
  `ConsoleGlyphPainter` draws all nine in one 24-unit design space at a single 1.6 stroke with
  round caps. Single weight is what makes a hand-drawn set read as instrument line-work.
  `nodeX` (hex + X) for delete ties the destructive action back to the board's own vocabulary.
- **Section captions** `PREFERENCES` / `SECURITY` / `SESSION` (new ARB keys in BOTH
  `app_pl.arb` — the template — and `app_en.arb`) copy the type of the ALREADY-SHIPPED Appearance
  sub-screen (`appearance_screen.dart:197`, its `COLOR THEME` labels) so root and sub-screen speak
  one dialect. Grouping is `PREFERENCES`, not `APPEARANCE`, to avoid "APPEARANCE › Appearance".
- **The Appearance row keeps the real `AppearancePreview`**, hex-clipped and deliberately
  OVERSIZED (92×58 in a ~38×44 window). The miniature paints its own radius-12 border; at
  anything near the hex's size that border cuts visible arcs across the interior.
- Every action preserved: profile, appearance, language, privacy, blocked, devices, web push,
  reset password, delete, logout, about link, version, uninstall warning. The old floating
  "person" badge is gone — tapping the core opens your card.

## 4. The bus (`2b646c1`) — variant B, after the owner explained what it means

Asked what the rail *means*, the owner gave the answer that settled it:

> "hexes looking like a honeycomb so the rail is highlighting the honeycomb in a technological
> way, my idea was to create something that looks like inside a computer — honey shapes, a
> technologically used honeycomb shape connected by lines, which is to visualize the
> technological transfer of information from the local node — the user's avatar — to other
> contacts. In the settings, it is supposed to be connected to each line coming from the avatar
> as if it were connected to it."

So the rail is **the local node's own bus**. Every settings row is a FACET OF YOUR OWN NODE, so
wiring each back to the core is literally true — which is the test my earlier "it means nothing"
objection failed. Objection withdrawn on the record.

> **This does NOT contradict the "no bus / no shared-rail wiring" rule on the Contacts board.**
> That rule stops the honeycomb implying contact-to-contact relationships that do not exist;
> there every drawn line must be one real user→contact edge and the node count must not lie.
> Settings has exactly ONE node and the rows are its parts. Written into
> `settings_console.dart`'s header too, because an agent citing that rule would delete the spine.

- `ConsoleSpinePainter` paints rail + stub **per row**, so it scrolls, reflows and re-themes for
  free and can light row by row. `ConsoleSpineHead` takes the bus out of the core's **WEST** tick.
- **The doubled gutter was resolved by MERGING the two signals, not moving one.** A marked row has
  no left border any more; the bus itself lights (`danger` → rail and stub in `error`,
  1.6px @ 0.95). The wiring carries the warning instead of running parallel to it.
- **Only `danger` lights the bus.** See the trap below.

## 5. Two render-caught defects, and one bug that recurred

1. **Light theme merged Delete Account and Log out into one alarm block** (first round). Both rows
   had a 5% wash and light's `primary` is nearly the same ember as `error`, so the washes ran
   together — logging out looked as destructive as deleting your account. Fixed: the filled wash
   is destructive-only.
2. **The same bug came back on the bus.** Lighting the rail for both `danger` and `accent` painted
   one continuous bright rail across the two adjacent rows — the identical merge, relocated from
   the border to the bus. Fixed: `busLit = edge == ConsoleRowEdge.danger`. Log out is marked by
   its tinted hex and title alone and terminates the bus with an end cap.
   *Falsified:* flipping `busLit` back to `edgeColor != null` gives `Expected: false, Actual: true`.
   **Both times this was caught only by looking at a light-theme render. It now has a test.**
3. **Language chips overflowed** at 320px × textScale 1.6: `Polski` + `Angielski` is ~210px of
   non-flexible trailing, crushing the title to one letter per line. Now `PL`/`EN` codes with the
   full name on the semantics node. *Falsified:* restoring the words gives
   `RenderFlex overflowed by 79 pixels`.
4. **Variant B's first render dropped the rail through the centred `LOCAL NODE` caption**, because
   the elbow derived the core centre from the block's mid-height instead of the avatar. Leaving via
   the west tick is the fix.

## 6. Incidents and traps paid for today

- **NEVER run `dart format lib/`.** It reformatted **70 untouched files**, including
  `main_shell.dart`, which must stay byte-identical to master. Caught it via `flutter analyze`
  surfacing 3 lints in files I had not opened, then reverted everything except the two files I
  actually edited and re-verified `git diff --stat 5a757d3 -- .../main_shell.dart` is empty.
  Format only the files you touched.
- **Tip ≠ deployed, three times.** Worst instance: a `LATEST.md` note asserting "branch tip IS
  the live deploy" was falsified by the very commit that recorded it. Then the replacement said
  "one docs-only commit ahead", which the next docs commit would also have falsified. Final
  wording is count-free. **Read `/version.json`; never infer what is live from `git log`.**
- **Proving a branch bundle is fresh when semver does not move.** Two methods, use one:
  (a) grep the served `main.dart.js` for a string literal new in this build — the `a342640`
  deploy was proven with `PREFERENCES` / `PREFERENCJE` / `SESJA` / `LOCAL NODE`. A matching
  `gitCommit` alone is weaker: it is a dart-define and recompiles even when other units are
  reused. (b) When the change adds no new string — the bus is pure painter code — `flutter clean`
  before `deploy-web.ps1`, which is what `18c97a9` did.
- **`flutter run -d web-server` cannot hot-restart the browser** (it warns about the Dart Debug
  extension). `R` recompiles but the tab keeps old pixels; `page.setCacheEnabled(false)` is not
  enough either. **Restart the harness process** for a real recompile. Cost me two rounds of
  screenshots that were byte-identical to the previous ones.
- **Screenshot readiness must be observed, not slept on.** A fixed 5s wait after a theme switch
  captured two blank frames that were then saved over good renders. Poll until the screenshot
  exceeds a size threshold instead.
- `tab.screenshot()` returns an object with a `dest` temp path, not a Buffer — copy the file.

## 7. Verification

- `flutter analyze --no-fatal-infos` over `lib/` AND `test/`: **0 issues**.
- `flutter test`: **827 passed / 4 skips** (was 821 at pickup). Backend untouched at **536**.
- New tests: `test/screens/settings_console_test.dart` (5 — shared core, no chevrons, wash is
  destructive-only, bus lights destructive-only, 320px×1.6 with a real title-width assertion),
  plus the contact-run re-arming test in `contact_network_view_test.dart`.
- Deploys: `a342640` then `18c97a9`, both ephemeral branch builds, `post-deploy-smoke.mjs`
  **5/5** each. Live: frontend 0.0.128/`18c97a9`, backend 0.0.127/`3861166`.
- Renders committed to `docs/design/settings-console/` (cosmic/light/blue for the console,
  cosmic/light for the spine and the shipped bus) with the full design rationale in `NOTES.md`.
- Harness: `test/preview/settings_preview.dart` mounts the REAL screen against seeded providers.
  Both throwaway prototypes were deleted once they had answered their question.

## 8. Open

- **Awaiting the owner's device pass on `18c97a9`.** Specifically flagged to him: whether the rail
  reads as too enclosing in the light themes, and whether the red segment at Delete Account is
  strong enough now that it lost its border.
- **Trunk vs literal fan — undecided.** His words say "each line coming from the avatar", which
  could mean N rays fanning from the core rather than one trunk with stubs. He approved the trunk
  from a render. The fan is a **modest** change: ~12 children need no laziness, so `ListView` →
  `SingleChildScrollView` + `Column` in a `Stack` lets one full-height painter draw real rays with
  measured positions; cost is that swap plus two tests asserting `find.byType(ListView)`
  (`settings_screen_scroll_physics_test`, `settings_screen_version_footer_test`). **The Contacts
  fan-revert reason does NOT apply** — that failure was N rays converging on a 34px rim at 100
  contacts; nine rows render fine.
- **Settings SUB-screens are still the old app.** `privacy_safety_screen.dart` and
  `blocked_users_screen.dart` already use the project's `GlassTopBar`, but their content is stock
  `Icons.verified_user/key/devices/laptop/terminal/block` with no hexes, so tapping "Privacy &
  Safety" from the new console lands somewhere half-converted. Appearance is the third.
- **Release path, still gated on his explicit OK:** bump 0.0.128 → **0.0.129** (PATCH, never
  `+N`) as the last commit on the branch, merge PR #97, `deploy-web.ps1` from master, smoke.
- Three reviewer-flagged judgement calls from the earlier round remain deliberately unaddressed
  (duplicated natural-sort comparator, back-to-back `switch (weight)` in `conversation_tile.dart`,
  ~20-param `ContactNetworkView`) — unasked-for, and they re-open review surface on a reviewed
  branch.

---

## 9. POSTSCRIPT — the bus was reverted on a physical phone (`8029424`)

After `18c97a9` was deployed, the owner opened it on his actual phone:

> "sorry now when i see it on the phisical phone i noticed the other option was a better choice
> please revert it to the previous one"

**Variant A — the console without the spine — is final.** No hedging: the bus was rendered in
three themes, reviewed, tested, falsified, deployed and smoke-verified, and it was still the
wrong call once it was in a hand. Every render in `docs/design/settings-console/` is 390×844 at
2× on a desktop monitor, and none of them reproduce a phone at arm's length, where a
full-height rail reads much heavier and more enclosing. This file's own §4 flagged "it encloses
the page" as a risk and the renders were not enough to settle it. **The device pass is not a
formality; it is the only thing that catches this class of error.**

### How it was reverted

`git checkout a342640 -- settings_console.dart settings_screen.dart settings_console_test.dart`
— restoring the three files to a build he had already approved, verified with
`git diff a342640 -- <files>` coming back empty. That beats hand-unpicking the diff, which is
where a subtle leftover would hide. `grep` for `ConsoleSpine|kConsoleSpineX|terminatesSpine|busLit`
across `lib/` and `test/` returns nothing.

**Kept on purpose:** `test/preview/settings_preview.dart` (mounts the real screen; useful every
round), all renders including `bus-*.webp` and `spine-*.webp`, and the design rationale in
`NOTES.md` — the bus section is retitled as history rather than deleted.

### A third freshness check, for REMOVALS

Neither prior method proves *absence*: `flutter clean` proves the build is fresh, and there is no
new string to grep when you are deleting painter code. Compare bundle size against the known-good
build instead:

| build | served `main.dart.js` |
|---|---|
| `a342640` (A, no bus) | 6,867,805 B |
| `18c97a9` (A + bus) | 6,869,132 B |
| `8029424` (revert) | **6,867,805 B** |

Landing exactly on the A size is corroborating evidence the bus code is genuinely gone, not just
that the bundle recompiled.

### Final state

`flutter analyze` over `lib/` and `test/`: 0 issues. Suite back to **826 passed / 4 skips** (the
bus-lighting test went with the feature). Live: frontend 0.0.128/`8029424`, backend
0.0.127/`3861166`, smoke 5/5. Master untouched, PR #97 open, no version bump.

**Do not re-apply `2b646c1`.** If the wiring is ever retried, the literal fan — N rays from the
core, which the owner's words may actually have described — was never put in front of him, and
any new attempt has to beat "a full-height rail is too heavy on a phone".
