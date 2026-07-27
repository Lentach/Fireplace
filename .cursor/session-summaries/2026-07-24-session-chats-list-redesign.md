# Chats list redesign — hex avatars, lit unread, row weights

**Date:** 2026-07-24 — owner approved the prototype renders ("hexes are very visual good loking design ... thats what we need go implement it"). Built for real on `feat/contact-network`, live as ephemeral deploy `ed037e5` / 0.0.128, smoke 5/5.

## What was done

1. **Shared hex** — new `frontend/lib/widgets/hex_avatar.dart`: `hexPath`, `kHexWidthRatio`, `HexClipper`, `hexInitials`, `HexAvatarSurface` (image/initials fill, AvatarCircle URL resolution, error+loading fallback) and the list-ready `HexAvatar` (sized, clipped, hairline ring, optional ember) + `HexRingPainter`. `contact_network_view.dart` now consumes them; its `_HexClipper`/`_HexAvatar`/`_hexPath` are gone and `_HexChromePainter` (focus halo) stayed private. The honeycomb renders identically — its 14 contract tests pass untouched.
2. **`ConversationTile` row weight** — derived from data the tile already receives, no new params, no backend:
   - `live` (unread > 0 or typing): 50px hex, 12px vertical pad, **second preview line**, lit 3px accent leading edge, 5% primary wash, accent bold time.
   - `normal`: 44px hex, 10px pad → **row height unchanged at 64px** (owner's Chats/Contacts parity rule).
   - `cold` (`_coldAfter = 6 days` since the last message): 36px hex, 7px pad, muted name, smaller preview.
   - Unread pill deleted; the count now rides next to the time in accent weight.
   - Ember: `HexAvatar.ember` = recency 1→0 across the same 6-day window.
   - Preserved verbatim: `Dismissible` swipe + `GlassDialog` confirm (restored from git after an early rewrite drifted), `Material`/`InkWell`, active-conversation bg, muted icon, typing line, `buildInlineEmojiSpans` preview, ephemeral `HearthFadeArcIndicator` via `countdownTickNotifier`.
3. **Lists** — `conversations_screen.dart` and the Contacts classic list switched `ListView.separated` → `ListView.builder` (dividers fought the new hierarchy). `contacts_screen._buildContactTile` uses `HexAvatar(size: 44)` with `EdgeInsets.fromLTRB(21, 10, 12, 10)` so its hex sits on the same vertical line as a chat row's (4+6+3+12 = 4+21) and the row stays 64px.
4. **Harness** — `test/preview/glass_preview.dart` mirrors production (no separators, tail rows aged 7+ days so the cold density is visible). The throwaway pitch harness `chat_list_redesign_preview.dart` was deleted after approval; pitch renders live in gitignored `frontend/build/chat-list-pitch/`.

## Key files

- `frontend/lib/widgets/hex_avatar.dart` (new), `frontend/lib/widgets/conversation_tile.dart`
- `frontend/lib/widgets/contact_network_view.dart`, `frontend/lib/screens/conversations_screen.dart`, `frontend/lib/screens/contacts_screen.dart`
- `frontend/test/widgets/conversation_tile_density_test.dart` (new), `frontend/test/preview/glass_preview.dart`

## Verification

- `flutter analyze`: 0 issues. Full suite **810 passed / 4 skips** (was 804): 6 new row-weight contracts — live > normal > cold heights, typing counts as live, normal row stays 64px+4 outer, count is accent text not a white-on-primary pill, avatar is `HexAvatar`, and a live row at **textScale 1.6 on a 320px screen throws no overflow**.
- Visual loop on the REAL tile via `glass_preview.dart`: dark, light, blue, teal at 390×844, top and scrolled (cold rows). Contacts classic list re-checked via `contact_network_preview.dart?screen=1` → list toggle: hexes aligned with chat rows.
- Deploy `ed037e5`: `/version.json` gitCommit `ed037e5`, served `main.dart.js` contains `ed037e5`, smoke 5/5. Backend untouched 0.0.127/`3861166`. `graphify update .` run.

## Notes for next session

- Branch `feat/contact-network` now carries BOTH the Contacts honeycomb + header search AND the Chats list redesign. Still unmerged, still 0.0.128, master untouched. Release path unchanged: PR → bump **0.0.129** → merge on explicit owner OK → master deploy + smoke.
- Owner's next-phase plan (agreed, not started): Contacts becomes **People** (absorbs add-friend / invitations / blocked, pending-request port on the core reticle), the Chats `+` opens the honeycomb as a picker, and #3 long-press hex → straight into the chat.
- Ember is the most droppable piece if it reads as noise on device: `ConversationTile._ember` + `HexAvatar.ember` — one line each.
- Trap paid: rewriting a widget's `build` from memory silently rewrote the swipe-confirm dialog (invented `l10n.deleteConversation`, wrong `GlassDialog.title` type, different delete background). Always `git show HEAD:<file>` the block you are not intentionally changing.
