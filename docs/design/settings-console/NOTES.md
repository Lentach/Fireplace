# Settings tab: the local node console

**Question (owner, 2026-07-25):** the Settings tab "looks like a different app" next to
Contacts and Chats. The local node is a CIRCLE, not a hex, so the avatar stays round —
everything else was up for rework. What should it look like?

**Answer: variant A, "local node console". Shipped.** Variant B (A plus a trace spine down
the left gutter) was built, rendered, and **not** taken.

The prototype (`frontend/test/preview/settings_console_prototype.dart`) has been deleted —
variant A is now the real screen, so the prototype's copies would have rotted immediately.
The renders in this folder are of the REAL `SettingsScreen`.

## What was wrong, concretely

All from the pre-rework `settings_screen.dart`:

| Smell | Where | What Contacts/Chats do |
|---|---|---|
| Zero hexagons | whole file | everything is built on `hex_avatar.dart` |
| A tinted glass card per row | `_settingsTileShell` | opaque rows (playbook §1: glass = floating chrome only) |
| Stock Material glyphs + a chevron on all 8 rows | `ListTile(leading: Icon(...))` | no chevrons at all |
| Radius soup: 16 / 20 / 8 / circle | tiles, lang pills, logout button | hex + SPEC 26/16 |
| Hardcoded `Colors.white` ×2 | avatar badge, logout button | tokens only |
| 8 flat tiles then 4 loose `Padding`s | the `ListView` body | structured |

## What shipped

- **The local node is now literally the same object as the Contacts core.** `LocalNodeCore`
  (`lib/widgets/local_node_core.dart`) was extracted out of `contact_network_view.dart`'s
  private `_LocalReticlePainter` and is consumed by BOTH. It stays a circle on purpose —
  that shape difference is what marks it as the local node.
- **Hex-leading opaque rows** at the same 44px hex / left offset 12 / 12px gap that the Chats
  list and the Contacts classic list already use (the owner's row-parity rule). No cards,
  no dividers, no chevrons — the row is the affordance.
- **The glyphs inside the hexes are drawn, not Material** (owner: *"dont forget to also change
  whats inside those hexes"*). `ConsoleGlyphPainter` draws all nine in one 24-unit design
  space at a single 1.6 stroke weight with round caps, which is what makes a hand-drawn set
  read as instrument line-work instead of clip art.
- **Section captions** (`PREFERENCES` / `SECURITY` / `SESSION`) copy the type of the
  already-shipped Appearance sub-screen (`appearance_screen.dart` — its `COLOR THEME` /
  `CHAT BACKGROUND` labels) so the root and the screen it opens speak one dialect.
- **The Appearance row keeps the real `AppearancePreview`**, hex-clipped and deliberately
  oversized: the miniature paints its own radius-12 border, and at anything near the hex's
  size that border cuts visible arcs across the interior.

## Two defects the RENDER caught that the code review did not

1. **Light theme merged Delete Account and Log out into one alarm block.** Both rows had a
   5% wash, and on the light themes `primary` is nearly the same ember as `error`, so the two
   washes ran together and logging out looked as destructive as deleting your account. Fixed:
   the filled wash is now reserved for `ConsoleRowEdge.danger`; `accent` is edge-only.
   Pinned by `settings_console_test.dart`.
2. **Variant B's spine collided with the lit row edges.** The rail sits at x=6 and the
   danger/accent edges are a 3px border at x=0 — in the SESSION block they fight for the same
   gutter. B also carries no information: on the Contacts board a trace means "this contact
   connects to your node", which is real, whereas a Settings rail connects rows to nothing.
   **If B is ever revisited, that gutter conflict is the thing to solve first.**

An earlier B render also dropped the rail straight through the centred `LOCAL NODE` caption,
because the elbow derived the core centre from the block's mid-height rather than the avatar.
Leaving via the west tick is the fix.

## Renders

Real `SettingsScreen`, 390×844, English, top of page + the SESSION block:

- `settings-console-cosmic-top.webp` / `settings-console-cosmic-session.webp`
- `settings-console-light-top.webp` / `settings-console-light-session.webp`
- `settings-console-blue-top.webp` / `settings-console-blue-session.webp`

## Still open

- The Appearance / Privacy / Blocked **sub-screens** still use glass cards. The root now
  speaks console; those screens are the next seam. Not in scope for this round.
- The old floating "person" badge over the avatar is gone — tapping the core opens your user
  card instead. Worth watching whether that reads as tappable on a device.

## Addendum — variant B re-rendered on the shipped console (2026-07-25)

The owner asked to see the other option again after A shipped. B was rebuilt as
*the real console plus a rail*, composing the production `SettingsConsoleRow` /
`SettingsSectionCaption` / `LocalNodeCore` widgets so only the painter was throwaway. The
prototype has been deleted; these renders are the record:

- `spine-cosmic-top.webp` / `spine-cosmic-session.webp`
- `spine-light-top.webp` / `spine-light-session.webp`

**The earlier "the spine collides with the lit edges" verdict was too harsh and is corrected
here.** With the elbow leaving the core's west tick (instead of dropping from the south tick
through the centred caption), B renders cleanly. In the SESSION block the 3px danger edge at
x=0 and the rail at x=6 read as two parallel verticals ~6px apart — doubled, slightly busy,
but not merged. That is a real cost, not a defect.

The stronger argument against B is not visual:

- **The rail carries no information.** On the Contacts board a trace means "this contact
  connects to your node" — it is a real relationship, and the node count never lies. A
  Settings rail connects rows to nothing; it is decoration wearing the costume of the app's
  one load-bearing idiom. That cheapens the idiom everywhere else it is used.
- **It encloses the page.** A full-height vertical line down the left gutter indents and
  boxes the content, which is most noticeable in the light themes.

If B is ever adopted anyway, the two things to decide first are (a) what the rail *means*,
and (b) whether the danger edge moves, since a doubled left gutter is the price otherwise.
