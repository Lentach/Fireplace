# Contacts: search moved into the header capsule (Honeycomb Core follow-up)

**Date:** 2026-07-24 — owner picked **idea 2** ("i would go with option 2 lets see serchbar in the header"). The 54px search band under the header is gone; the Honeycomb field starts right below the header chrome.

## What was done

1. `frontend/lib/widgets/main_tab_screen_header.dart`
   - Added `MainTabScreenHeader.custom({required Widget child})`: replaces the whole capsule row while the header keeps owning the geometry (SafeArea + 14px insets + 52px capsule height). The standard path was extracted into `_buildCapsuleRow` — unchanged rendering.
   - Added `leadingGlass` (default `true`). Chats keeps its `GlassCircle`-wrapped avatar; Contacts opts out so its magnifier is a bare icon mirroring the bare trailing control. **Chats/Settings call sites untouched** (past regression: header edits broke Chats centering).
2. `frontend/lib/screens/contacts_screen.dart`
   - Deleted `_searchClearance = 54`, `_buildSearchBar`, and the `Positioned` band in `build`. `_buildNetwork.safeInsets.top` and `_buildContactsList.topClearance` are now just `media.top + MainTabScreenHeader.clearance`.
   - Header closed state: bare magnifier LEFT (`_openSearch`), title, list/map toggle RIGHT (extracted `_buildListToggle`, shared by both states).
   - Header open state (`_searchOpen`): `MainTabScreenHeader.custom` → `GlassPill(height: capsuleHeight)` spanning the row, inner magnifier + `TextField(autofocus)` + `×` (`_closeSearch`, tooltip `l10n.cancel`), **with the list/map toggle kept in its slot** so a query survives a view switch (the old flow could switch views mid-search; hiding the toggle would have removed that).
   - Escape closes via `CallbackShortcuts` (desktop parity with the network's Tab/Enter support).
   - `filtering` now also requires `allFriends.isNotEmpty`, so an account that loses its last contact while a query is live shows "No contacts yet", not "No matching contacts".
   - Search field decoration switched from `InputDecoration.collapsed` to explicit `InputDecoration(isCollapsed: true, …, focusedBorder: InputBorder.none)`: **`collapsed` only nulls `border`**, so `RpgTheme.inputDecorationTheme.focusedBorder` (2px primary, radius 8) painted a second box inside the glass capsule on focus. Confirmed by render, not by guessing — the DOM input has `outline: none`, the ring was Flutter-painted.
3. `frontend/test/screens/contacts_screen_search_test.dart`: 4 → 7 tests. New: magnifier swaps title for the field (toggle stays), no-band clearance contract (`ContactNetworkView.safeInsets.top == MainTabScreenHeader.clearance`), escape closes. Updated: every test opens search first; close restores title + full set; empty account has no magnifier at all.

## Key files

- `frontend/lib/widgets/main_tab_screen_header.dart`
- `frontend/lib/screens/contacts_screen.dart`
- `frontend/test/screens/contacts_screen_search_test.dart`

## Verification

- `flutter analyze --no-fatal-infos`: **No issues found**. Full suite: **804 passed / 4 skips** (was 801/4).
- Visual loop on the real screen (`test/preview/contact_network_preview.dart?screen=1`): cosmic 390×844 closed + open, light 390×844 with a live query, blue 320×700 open, and a typed query proving the live re-filter (`NODES 01`). Chats header re-verified separately via `test/preview/glass_preview.dart` on :8128 — glass avatar, centred "Chat", bare `+`, unchanged.
- `graphify update .`: 9264 nodes, 13226 edges.

## Notes for next session

- **Feature is complete pending owner review.** Nothing is merged: branch `feat/contact-network`, master untouched, no version bump, no deploy from this session (owner deploys on demand: `powershell -ExecutionPolicy Bypass -File deploy-web.ps1` from repo root, then `cd scripts/smoke && node post-deploy-smoke.mjs`).
- Release path when he approves: PR `feat/contact-network` → master, bump `frontend/pubspec.yaml` 0.0.128 → **0.0.129** (PATCH only, never `+N`), merge on explicit OK, master deploy + smoke.
- Design invariants unchanged and still owner-kept: one socket pin = no conversation, two = active chat; route strip on tap only (480ms), never on bare keyboard focus; real data only; theme tokens only.
- Full brief for the honeycomb itself: `2026-07-23-handoff-honeycomb-search.md` + `2026-07-23-session-honeycomb-core.md` (both local-only).
