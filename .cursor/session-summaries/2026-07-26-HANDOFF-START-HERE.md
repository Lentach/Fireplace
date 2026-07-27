# ⚠ START HERE — Fireplace pickup brief (2026-07-26, late)

**This was the current handoff for `feat/nav-rework`; that branch merged as PR #98 and
shipped, so this file is now HISTORICAL.** The banner-marked-superseded `*handoff*` files
were deleted on 2026-07-27. Note they were gitignored local-only files, so that deletion
is permanent — there is no git history to recover them from.

---

## 0. Bootstrap, in this order. Subagents inherit NOTHING — tell them to read these too.

This is AGENTS.md's mandated order (root → tier → LATEST), not a preference. The UI
playbook is not part of that sequence but is required before touching anything visual,
which on this branch is everything.

1. Root `CLAUDE.md`
2. `frontend/CLAUDE.md` (the tier file — all of this work is frontend)
3. `.cursor/session-summaries/LATEST.md`
4. **This file**
5. `2026-07-26-session-nav-rework.md` (the last round in full)
6. `docs/design/flutter-ui-playbook.md` — before your first visual change

---

## 1. State — verified against the repo and the live server, not recalled

| | |
|---|---|
| branch | `feat/nav-rework`, tip **`360c41a`**, pushed, in sync |
| ahead of master | **12 commits** over `92eeea5` |
| live | **0.0.129 / `2d48f7a`** — an EPHEMERAL BRANCH deploy, smoke 5/5 |
| backend | untouched, 0.0.127 / `3861166` |
| PR | **none open for this branch** — one must be created at merge time |
| `frontend/pubspec.yaml` | **0.0.129** — branch deploys never bump semver |
| master | **untouched by this branch**, tip `92eeea5` — that is the 0.0.129 release (`9d24d7b`) plus its LATEST.md commit |
| frontend tests | **876 passed / 4 skips** |
| backend tests | **536** — untouched, do NOT change the number in root `CLAUDE.md` §3 |
| `flutter analyze --no-fatal-infos lib/ test/` | 0 issues |
| `main_shell.dart` vs master | **changed on purpose**, +6 −100 (see §5) |
| working tree | clean except ~10 stray `.jpg`/`.mp4` in the repo root |

> **CORRECTED 2026-07-27 — the paragraph that was here is WRONG. Do not act on it.**
> It claimed the repo is PUBLIC and that dated session files are local-only. Both are
> false: `gh repo view --json isPrivate` returns `true`, and as of 2026-07-27 all 225
> dated summaries are tracked. The old text told agents not to commit this file and to
> scope every `git add` around it — ignore that. Root `CLAUDE.md` §1 is authoritative.
> Kept as a record of what the policy used to be, not as instruction.

**The stray media in the repo root are the owner's screenshots. Never touch them, never
`git add` them.** (Still true — they are gitignored at the root now, but do not commit
them deliberately either.) Scope your adds and run `git show --stat HEAD` before pushing.

**Never infer what is live from `git log` — read `/version.json`.**

---

## 2. The one remaining task

**Design is finished and approved end to end. The only thing left is the release, and it
is gated on the owner saying "merge".** He has approved the work ("yup thats it"); that
is not approval of a release.

**On an explicit "merge", in this order:**
1. Bump `frontend/pubspec.yaml` 0.0.129 → **0.0.130** (PATCH; never `+N`) as the LAST
   commit on the branch.
2. `gh pr create` and merge it — unlike last time, no PR exists yet.
3. `cd C:/Users/Lentach/Desktop/fireplace && powershell -ExecutionPolicy Bypass -File deploy-web.ps1`
   from master (NOT `.\` under bash).
4. `cd scripts/smoke && node post-deploy-smoke.mjs`
5. Dated summary + LATEST edit-in-place (cap 5).

---

## 3. What this branch actually contains

The bottom nav, rebuilt in the console language. Every decision below is the owner's,
taken from a render or from his phone.

| | Resting | Selected |
|---|---|---|
| **Chats** | hex speech bubble + tail | inner cell fills with two message lines knocked OUT of the fill; the bubble lifts and settles |
| **Contacts** | three cells sharing edges | three INSET cores flood in sequence; the cells fly apart and reassemble |
| **Settings** | gear wearing the cell | stroke weight 1.8 → 2.5; turns one tooth pitch |
| **The pill** | — | a **glass lens** glides under the active tab, sweeping THROUGH any slot you skip |

Plus: the Settings console's `language` glyph is now a meridian globe, and
`ConsoleGlyph.localNode` was renamed `.settings`.

---

## 4. DO NOT RESURRECT — everything that was built and rejected

Each of these was drawn, rendered, usually deployed, and killed. Rebuilding one wastes a
round and annoys him.

- **The selection BAR** — *"it cover it delete it"*. (It was also genuinely broken: a
  greedy `Center` parked it in the middle of the pill so it cut through the glyph.)
- **The hex SOCKET** framing the active tab — *"looks messy, outer line is too small for
  nav icone"*.
- **The travelling NODE** on a dormant rail — *"its mid i dont like it"*.
- **The scale PULSE** (1.0→0.92→1.06→1.0) — *"pulse is not it … too little animation"*.
- **The `PathMetric` DRAW-ON** — *"only gear is moving, rest is static"*. A stroke reveal
  at 24px reads as a plain colour change.
- **FLUSH fills** on any glyph — *"chat icone is all black"*. A closed silhouette filled
  to its own outline is one black mass, worse on light themes where the accent is nearly
  black.

**The rule all of that taught: on this pill, small hard-edged markers lose to edgeless
light.** The lens that finally landed has no edge at all.

Also still on the do-not-resurrect list from earlier branches: the local node **bus**, the
**power-on scan**, and the Contacts **rim fan**.

---

## 5. Hard rules

- **NEVER merge to master, bump the version, or deploy master without explicit owner OK.**
- **`main_shell.dart` is no longer byte-identical to master, and that is correct now** —
  the nav destinations live there, and the 100 deleted lines are the bespoke chat-bubble
  painter that existed only for the old Material icon. The old "must stay byte-identical"
  rule died with this branch. Do not "restore" it.
- Theme tokens only — `RpgTheme`, `FireplaceColors.of`, `GlassTheme.of`, `colorScheme`.
  Zero `Color(0x...)` in screens/widgets.
- Content surfaces are OPAQUE. Glass lives only on floating chrome (`SPEC.md` §1).
- **Only `danger` ever gets a filled wash.** Light theme's `primary` is nearly the same
  ember as `error`, and Delete Account / Log out are adjacent. This bug has occurred twice.
- 7-provider cap; `instant_opaque_route` untouched; the 480ms route fill is RATIFIED.
- **`dart format <touched files>` ONLY — never `dart format lib/`.**
- Falsify every behavioural test you add: break the code, see red, restore. Every test on
  this branch was falsified.
- `graphify update .` after code changes. LATEST.md hard cap 5 entries (the pre-commit
  hook BLOCKS at 6). Dated summaries are gitignored BY DESIGN; only `LATEST.md` is tracked.

---

## 6. How he works — the single most important section

- **He tests on a physical phone and that verdict overrides renders, tests and review.**
  Renders are ~1.6× the physical size of his handset.
- **Renders keep flattering things his hand rejects.** Several treatments passed a render
  this session and failed on device. Use renders to pick a DIRECTION; deploy to get a
  VERDICT. Do not present a render as proof.
- He picks well from rendered A/B variants, per row. That workflow has now worked four times.
- Informal English, terse, rejects fast, and **reverses himself when shown meaning** — so
  show, don't argue. He also mistypes: *"gears on is all black"* was corrected to the CHAT
  icon a message later. **When a verdict is ambiguous, ask or check — do not record a
  rejection he did not make.** (I logged two device rejections where there was one.)
- **Judge your own render before showing him.** That caught the flush-fill blob and the
  zero-width lens. It did not catch the 45° error or the socket, so also state plainly
  which calls are yours versus his.
- **The browser tool is NOT headless.** It pops a real Chromium window in front of him.
  Announce it, batch every capture into one session, then `close` (`all`+`kill`) +
  `hub stop` immediately.
- He cannot read tall screenshots in chat. **Save renders as real JPEGs to
  `C:/Users/Lentach/Desktop/` and open them** (`start "" <path>`); verify the bytes are
  `ffd8ffe0`. Upscale ~1.6× — he could not see the first one at native size.

---

## 7. Expensive knowledge from this round

- **A decoration-only child inside a `Center` collapses to ZERO WIDTH.** The glass lens
  rendered nothing until it was given a real width. Loose constraints + no intrinsic size
  = invisible.
- **Sampling tests against fast animations need side-of assertions, not window
  assertions.** The lens sweeps ~50px per frame at peak, so a 6px window around the
  midpoint is jumped clean over; assert samples on BOTH sides instead. The same trap ate
  two earlier pulse tests, which passed with the feature deleted.
- **`Path.contains` is the honest way to assert a knockout.** Comparing contour counts
  proves nothing. Remember geometry is re-centred on resolve, so shift design-space
  coordinates by `fill.getBounds().center - <raw centre>` first.
- Filling the comb's three shared-edge cells FLUSH merges them into one lump. The fills
  are inset for that reason, and its stroke deliberately does not thicken — widening it
  would eat the ~2.4-unit gap holding them apart.
- **The LSP index goes stale** on new enum members and renames; `flutter analyze` is
  authoritative. Do not chase phantom errors.
- `hub` `op:"start"` cannot spawn `flutter` on Windows — it is a batch file. Use
  `application: "cmd.exe"`, `args: ["/c", "C:\\flutter\\flutter\\bin\\flutter.bat", ...]`.
- Screenshot readiness: `networkidle2` + a fixed 6–8s settle. Never poll for byte-size
  stability. `tab.screenshot()` returns an object with `dest`, not a Buffer.
- The Python eval kernel loses imports between distant cells — re-import `PIL`/`subprocess`
  rather than assuming they survive.

---

## 8. Commands

```powershell
# deploy (from repo root, PowerShell, NOT .\ under bash)
powershell -ExecutionPolicy Bypass -File deploy-web.ps1
cd scripts/smoke && node post-deploy-smoke.mjs

# render harnesses (background job; ALWAYS stop them)
flutter run -d web-server --web-port 8099 -t test/preview/glass_preview.dart
#   ?screen=settings|appearance|privacy|blocked|chat|desktop|auth|dialogs
#   &theme=cosmic|blue|dark|light|teal
flutter run -d web-server --web-port 8098 -t test/preview/console_glyph_sheet.dart
flutter run -d web-server --web-port 8097 -t test/preview/settings_preview.dart
flutter run -d web-server --web-port 8096 -t test/preview/contact_network_preview.dart
```

Throwaway A/B harnesses are written under `test/preview/` and DELETED after each pick —
that is deliberate, do not treat their absence as missing work.

Owner's PWA: full close + reopen. **NEVER** uninstall or clear site data — it wipes the
on-device E2E Signal keys with no recovery.

---

## 9. Key symbols

- `lib/widgets/console_glyphs.dart` — `kGlyphUnit/kGlyphBox(24)/kGlyphStroke(1.8)/
  kGlyphStrokeActive(2.5)/kGlyphKeylineExtent(8.2)`, `ConsoleGlyph` (18 members: 15
  Settings rows + `chats`/`contacts`/`settings`), `ConsoleGlyphGeometry{strokes,fills,
  dots,activeFills,bounds,shift,centred}`, `_activeStroke`, `_selectedSpin`, `_bump`,
  `_motionOffset`, `_regionProgress`, `ConsoleGlyphPainter{progress,activeColor}`,
  `ConsoleGlyphIcon`.
- `lib/widgets/icon_selection.dart` — `IconSelection{progress,activeColor}`. The seam that
  keeps `GlassBottomNav` icon-agnostic and `ConsoleGlyphIcon` nav-agnostic.
- `lib/widgets/glass/glass_bottom_nav.dart` — `GlassBottomNav`, `_NavItem`,
  `kTintDuration(200)/kEntranceDuration(340)/kExitDuration(200)/kTravelDuration(300)/
  kLensHeight(50)/activeLensKey`.
- Tests worth knowing: `test/widgets/console_glyph_keyline_test.dart` (keyline for all 18
  glyphs, filled-variant policy, comb seams, comb fill/cell pairing, the bubble's knockout
  lines), `test/widgets/glass/glass_bottom_nav_test.dart` (semantics, hit targets,
  entrance/retract/reduce-motion, lens dock/sweep/snap).

---

## 10. Queued, none promised

- **Unresolved from the merged branch:** `ConsoleGlyph.appearance` renders nowhere (the
  live `AppearancePreview` owns that row's slot), and `push` is the one glyph he never
  named. Both are his forks — present them, do not decide them.
- `ListView` rewrite of the honeycomb for >200 contacts — deliberately deferred.
- "Sent invites as ghosts" — needs a backend change to `friends.service.ts
  getPendingRequests`, which filters `receiver: { id: userId }`.
- Chats `+` as a honeycomb picker; blocked users moving out of Settings.
- A **Dependabot high-severity alert** on master keeps appearing on every push:
  https://github.com/Lentach/Fireplace/security/dependabot/95 — never triaged, worth raising.
- If he ever wants richer icon motion than paths can express, the next real step is a
  Rive/Lottie dependency with an authored file per icon — more expressive, at the cost of
  a dep plus an asset per glyph.
