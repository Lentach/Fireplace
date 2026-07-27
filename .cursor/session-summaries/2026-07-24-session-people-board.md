# People board + long-press to chat

**Date:** 2026-07-24 — owner: "long-press hex → straight into chat, press user card - implement it yes" and then "implement it as you wish you have a free hand" for Contacts → People. Both built on `feat/contact-network`; live as ephemeral deploys `6a23335` (long press) and `d8fd24f` (People board), smoke 5/5 each.

## What was done

### Long-press → chat (`6a23335`)
- `ContactNetworkView` gained `onContactOpenChat` + `openChatSemanticHint`. Tap is unchanged (480ms route fill → user card). Long press, or **Shift+Enter** on a focused hex, calls `_openChat`: no route animation in front of the deliberately zero-duration `instantOpaqueRoute` chat entry.
- Gated by `_canOpenChat(contact)` = callback present AND `conversationContactIds.contains(id)` — **a stray long press can never create a conversation**; unwired contacts stay tap-only.
- Semantics: the node switched to `Semantics.fromProperties` (this Flutter's `Semantics` has no `hintOverrides` param) so the long-press action carries `SemanticsHintOverrides(onLongPressHint: "Open chat")`, wired only where a wire exists. New ARB `contactNetworkOpenChatHint` (en+pl).
- Haptic `selectionClick` guarded with `!kIsWeb`, matching `recording_controller.dart` precedent.

### People board (`d8fd24f`)
- **Inbound port**: when `FriendsProvider.pendingRequestsCount > 0`, a chip (`↓ N`) with a stub docking into the top of the core reticle; tap → `AddOrInvitationsScreen`. Hidden while searching.
- **Add cell**: one trailing dashed hex with a `+` and an empty socket, caption "add". Tap/Enter → same screen. Implemented as `ContactHexLayout.resolve(extraSlots: 1)` + `ContactHexLayoutResult.extraSlots` — **geometry, not a synthetic contact**, so `NODES`, `contactNetworkSemantic(count)`, traversal order and `_applyQuery` all still count only real people. `onAddContact: filtering ? null : …` keeps a filtered board from growing one.
- Empty accounts keep the board: core + port + add cell, with the "No contacts yet" copy repositioned below the first row instead of colliding with it.
- `_HexFieldPainter` now guards `i < layout.inputs.length` (the add slot has no contact → single empty socket). That RangeError was caught by the existing screen tests, not by hand.
- New ARB (en+pl): `contactNetworkAddSlot`, `contactNetworkAddSlotSemantic`, `contactNetworkPendingRequests` (plural).
- Harness: `contact_network_preview.dart?pending=N` seeds inbound requests.

## Key files

- `frontend/lib/widgets/contact_network_view.dart`, `frontend/lib/screens/contacts_screen.dart`
- `frontend/lib/l10n/app_en.arb`, `app_pl.arb`
- `frontend/test/widgets/contact_network_view_test.dart`, `frontend/test/preview/contact_network_preview.dart`

## Verification

- `flutter analyze`: 0 issues. Full suite **816 passed / 4 skips**. New contracts: long press opens chat and not the card, long press on an unwired contact does nothing, semantics expose the action + hint only where wired, the add cell taps through while `inputs` stays at the real count, an empty account still offers the add cell with the copy below it, the port appears only when requests wait and taps through.
- Visual (`?screen=1`): cosmic 390×844 with 7 contacts + add cell (NODES 07 unchanged), `pending=3` showing the docked port, light theme with an empty account.
- Deploys verified by `/version.json` gitCommit + served `main.dart.js` sha; backend untouched 0.0.127/`3861166`. `graphify update .` run.

## Notes for next session

- **Deferred deliberately: "sent invites as ghosts".** `friends.service.ts getPendingRequests` filters `receiver: { id: userId }`, so the client only ever receives INBOUND requests — ghosts need a new backend query + socket payload. Told the owner rather than widening into `backend/` under the free-hand mandate.
- Also not built: Chats `+` opening the honeycomb as a picker, and moving blocked users out of Settings.
- Owner must verify the long press **in the installed PWA**: iOS Safari can eat long-presses over a canvas with its own callout. Fallback if it misfires: double-tap or a socket-sized tap target.
- Branch still unmerged at 0.0.128; release path unchanged (PR → 0.0.129 → merge on explicit OK).
