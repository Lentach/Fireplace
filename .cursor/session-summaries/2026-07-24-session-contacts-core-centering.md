# Contacts board: core centering, node borders, add-cell placement, view-mode memory

**Date:** 2026-07-24 — branch `feat/contact-network`, deploys `970f906` then `9d968c7` (0.0.128, ephemeral branch builds). Owner nit round after his on-device test of `38c12e8`.

## Owner input this round

His verdict on `38c12e8`: **long press → chat works on the phone** (the iOS-eats-long-press risk did not materialise; no double-tap fallback needed). Then five items:

1. "the user cube should have borders"
2. "the connectable node should have no border inside its circle"
3. "add hex is showed last i need to scroll to the bottom to get it with 27 nodes, im not sure where to put it tho lets brainstorm it"
4. "any twaks visuals wow effects you wont to add or propose? suprise me with somthing inside computer theme"
5. (screenshot, 27 nodes, light/PL) "users alteregobob8 and benz93 their lines are not fully connected to the local note, i think lokal node is not on the center of the screen it sligdly moved"
6. (mid-session) "when user change view contacts to tails it shold remeber decision and next time user enter this tab it remeber tile style not nodes, now its always node"

## What was done

1. **Core off-centre + detached wires — one root cause.** `_buildCore`'s `Positioned` had `left`/`top` only, so the `Column` shrink-wrapped to its widest child — the `LOCAL NODE` caption (~96px), not the 68px reticle. The Column then centred the avatar in that wider box, pushing the drawn core `(captionWidth - 2*coreRadius)/2` ≈ 17px right of `layout.coreCenter`. Every feed line and route is aimed at `layout.coreCenter`, so on the LEFT side the wires started ~17px clear of the visible rim (owner saw it on alteregobob8/benz93) while on the right they hid under the shifted disc. Fix: the core sits in a full-width band (`left: 0, width: coreCenter.dx * 2`), so the avatar is pinned to the field axis and the caption can be any width. **This was invisible to analyze and to all 816 tests** — a regression test now asserts the rendered core centre and caption centre both equal the field centre within 0.5px.
2. **Node chrome: one visible border, none inside.** All three node painters were drawing in `colors.convItemBorder`, which on the light themes is `#E8E3DC` on `#FAF8F5` — a ghost. The wires beside them use `colorScheme.onSurface`, which reads fine, hence "should have borders". Painters now take `outline: colorScheme.onSurface` (param renamed `borderColor` → `outline`): hex outline 1.4px @ 0.42, dashed add cell @ 0.45, reticle ticks @ 0.45. The inner hairline at `r-3` inside every hex and the inner ring at `r-6` inside the local reticle are **deleted** (owner: borders on the cell, none inside it). `_HexFieldPainter` lost its `borderColor` param entirely — the field is now drawn in a single ink at varying alpha (lattice dots 0.16, stubs 0.38, pads 0.60, feed 0.30).
3. **Add cell moved from the tail to the HEAD of the field.** `extraSlots` → `leadingSlots`; the "+" is now `slots[0]`, contact `i` is `slots[i + leadingSlots]`. At 27 contacts the trailing cell sat seven rows down. Still geometry, never a synthetic contact: `inputs`, the `NODES` count, semantics and search stay honest. `_HexFieldPainter` maps slot→contact with `i - leadingSlots` (was a tail guard `i < inputs.length`). Traversal order: core (0) → add (0.5) → contacts (1..n).
   - **Considered and rejected:** docking a `+` port to the core's right beside the inbound `↓ N` chip. It was built, then reverted — there is no room for its caption next to the centred `WĘZEŁ LOKALNY` band at any text scale above ~1.2, and an unlabelled `+` hex touching the core reads as a contact socket. Tooltips do not exist on touch.
4. **A "power-on scan" entrance effect was built, deployed, shown, and DELETED at the owner's request.** Two iterations: first a wavefront inside `_HexFieldPainter` riding the row-latch envelope (its speed scaled with row count — on a 27-contact board it crossed the visible rows in ~100 ms and read as a flash), then a screen-fixed `_ScanSweepPainter` overlay on its own 620 ms controller, replaying on every tab entry. The second one rendered well in light and cosmic. His verdict: *"its not a wow effect its just a scan… get rid of it."* Removed in full — painter, controller, overlay, `_syncScanToVisibility`, the preview `tabloop` harness, and the test. **Do not rebuild it.**
5. **Contacts view mode persists.** `SettingsProvider.contactsListView` (bool, key `contacts_list_view`, device-local — a view preference, not per-account like `chat_wallpaper_<id>`). `ContactsScreen` dropped its local `_showList` and reads `context.select<SettingsProvider, bool>(...)` in both spots; the toggle writes through `context.read(...).setContactsListView(...)`. `select`, not `watch`, so a theme/locale/wallpaper change does not rebuild the honeycomb.
6. **Discovered and then deliberately left alone: the honeycomb entrance has never run on a device.** `MainShell` keeps all three tabs mounted in an `IndexedStack`, whose `build` wraps every child in `Visibility(maintainAnimation: true)` — an offstage tab's animations keep running. The honeycomb spends its whole 280 ms row-stagger at app boot behind the Chats tab and latches `_entranceCompleted` before Contacts is ever opened; it only ever looked right in `contact_network_preview.dart`, where `ContactsScreen` is the home widget. **This is now the accepted status quo:** with the effect gone there is nothing worth seeing, and content being already drawn on tab entry is the better behaviour anyway. Two traps paid for, if anyone revisits: (a) `TickerMode` mutes frame delivery but NOT the clock (`ticker_provider.dart:44` — "Time still elapses"), so a muted controller jumps straight to completed on unmute — gating on it does not defer anything; (b) holding an entrance tween at 0 until the tab is visible makes the board paint blank on the first frame of every entry, which reads as a flash — that regression is what the owner saw and reported. `MainShell` is back to byte-identical with master.

## Key files

- `frontend/lib/widgets/contact_network_view.dart` — `_buildCore` band, `_HexChromePainter`/`_AddSlotPainter`/`_LocalReticlePainter` (`outline` param, inner rings gone), `_buildAddNode` at slot 0, `leadingSlots` through `ContactHexLayout.resolve`/`ContactHexLayoutResult`/`_slotIndexOf`/`_buildContactNode`.
- `frontend/lib/providers/settings_provider.dart` — `contactsListView` / `setContactsListView` / `_loadContactsListView`.
- `frontend/lib/screens/contacts_screen.dart` — `_showList` deleted, `select`-driven view mode.
- `frontend/lib/screens/main_shell.dart` — touched during the scan episode, then fully reverted; byte-identical to master.
- `frontend/test/widgets/contact_network_view_test.dart` — +1 (core on the field axis), add-cell test rewritten for head placement.
- `frontend/test/screens/contacts_screen_search_test.dart` — harness gains `SettingsProvider` + `SharedPreferences.setMockInitialValues`, +2 (toggle persists through a remount with a FRESH provider and asserts the prefs write; a stored `true` opens in list on a cold start).
- `frontend/test/preview/contact_network_preview.dart` — `SettingsProvider` added to the seeded provider list (`screen=1` mounts the real `ContactsScreen`).

## Verification

- `flutter analyze --no-fatal-infos` → **No issues found**.
- `flutter test` → **819 passed / 4 skips** (was 816; +1 core-centre, +2 view-mode persistence).
- Deploys `970f906` then `9d968c7` → `scripts/smoke/post-deploy-smoke.mjs` **5/5** each (health, `/version.json` 0.0.128, backend 0.0.127/`3861166`, `main.dart.js` literally contains the sha, app boots). `graphify update .` → 9302 nodes. The final scan-removal commit is deployed on top.
- Rendered in light + cosmic at 390×844 (real `ContactsScreen`, 27 seeded contacts, avatars on) once the owner asked for screenshots. Confirms: core dead-centre with BOTH first-row feeds meeting the rim, hex outlines legible in light theme, no inner ring in the reticle, `+` as the first cell top-left, `NODES 27`.

## Notes for next session

- Master still `5a757d3`, still untouched. No version bump. Release path unchanged and still gated on his explicit OK: PR → bump 0.0.128 → **0.0.129** → merge → `deploy-web.ps1` from master → smoke.
- The three optional Standards findings from the review round are still open and still unasked-for: duplicated natural-sort comparator (`contacts_screen.dart` `_compareByDisplayName` vs `ContactHexLayout.compareByDisplayName`) + redundant double sort in `_buildNetwork`; back-to-back `switch (weight)` in `conversation_tile.dart`; ~20-param `ContactNetworkView`.
- **Chats and Settings were audited for the same offstage-entrance trap and are CLEAN** — neither has a one-shot entrance, only the fetch-gated skeleton shimmer, which has no "already played" latch.
- **Do not render with the browser tool while he is at the machine.** It is not actually headless. Either deploy to the branch and let him look, or find a genuinely offscreen capture path.
- Still on the do-not-resurrect list: **the power-on scan pass ("its just a scan")**, unread/typing status on the Contacts board, activity-based sorting, idle ambient animation on the field, contact-to-contact links.
