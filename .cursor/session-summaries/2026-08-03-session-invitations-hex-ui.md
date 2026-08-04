# Invitation surfaces speak hex — picker invite socket, hex badges/pills, hex chat-header avatar

**Date:** 2026-08-03 (worktree `fireplace-invitations-ui`, branch `feat/invitations-hex-ui`, NOT merged/deployed)

## Second pass — owner picked crazy ideas 2/3/4/5

All four implemented same session (Codex-backed `task` subagents died `usage_limit_reached` instantly — the documented Anthropic-only trap — so everything ran inline):

- **#2 Forge animation (`invitation_row.dart`):** `_ForgeHexAvatar` wraps the row avatar; on the pending→accepted transition a dashed accent hex overlays it, dash gaps close over 70% of 280 ms (dashOff 4→0), then fades — the pending-socket vocabulary soldering solid. One-shot via `didUpdateWidget`; element reuse across accept works because incoming and outcome rows share the peer-id key (the expanded card is a DIRECT sibling of outcome rows for exactly this reason — do not wrap it). Reduce-motion skips entirely. Tests: `test/widgets/invitation_row_forge_test.dart` (3).
- **#3 Hex "+" badge (`conversations_screen.dart`):** the pendingRequestsCount indicator on the Chats `+` is now `HexCountBadge` size 18, error/onError tokens — was the last `BoxShape.circle` count badge. (The 8px dot in `chat_action_tiles.dart` is not a count; conversation tiles deliberately have NO badge — owner-approved lit-edge design, untouched.)
- **#4 Honeycomb inbox (`invitations_screen.dart`):** pending inbound requests render as `_WaitingComb` — picker-math lattice (columns clamp 3–6, hex 56–72, odd-row half-cell stagger), keys `invitation-comb-<requestId>`. Tap toggles that sender's accept/decline card below (key = peer id). **A lone request AUTO-EXPANDS** (`_expandedRequestId` null = auto, `-1` = user-collapsed sentinel) — this is what kept every pre-existing single-request test green. +2 comb tests.
- **#5 Ping hex lattice (`ping_effect_overlay.dart`):** the two `BoxShape.circle` rings are `_PingHexPainter` hexes (same sizes/alphas/strokes, const-constructed so the build-once/no-per-frame-rebuild contract in the file's comments still holds; `Color(0x47FF9800)` etc. are exactly `Colors.orange` at the old alphas). Preview `?view=ping` remounts the overlay in a loop for screenshots.

Verification for this pass: analyze clean, full suite **1203 + 10 skipped** green (+5), visual loop: comb collapsed (3 requests) / auto-expanded (1) in dark, ping lattice in dark.

## First pass — what was done

Owner asked: an "invite a friend" door in the Chats `+` picker (same as the Contacts add hex), hex-shaped count badges instead of round circles in the Invitations tab, a general de-genericizing of that tab, and a hex avatar in the chat screen header. All on a fresh worktree.

- **`HexPill` (`widgets/hex_pill.dart`, NEW) + `HexCountBadge` (`hex_avatar.dart`, NEW):** the count badges are the app's EXACT pointy-top `hexPath` hexagon (`HexCountBadge`; owner interjection — the first cut used a flat-top elongated hex and was rejected: "must be exact hex as rest of them"). `HexPill` (elongated 120°-cap hexagon) survives ONLY for word pills — `InvitationStatusPill` ("Pending"/"Chat ready") — because a regular hexagon cannot hold a word. Colors/kinds unchanged; only shapes moved off `borderRadius: 999`.
- **`DashedHexPainter` (public, `hex_avatar.dart`):** replaces the two private dashed painters in `contact_network_view.dart` (add cell 5/4 runs, ghost 8/4 + fill — visuals identical) and paints the picker's new socket. One dash vocabulary, three callers.
- **Chats `+` picker (`chat_honeycomb_picker.dart`):** new sealed choice `ChatPickerInviteNew`; the comb now ends in a dashed "+" socket (key `chat-picker-invite-new`, caption/semantics reuse `contactNetworkAddSlot*`). The EMPTY picker instead carries an `Invite someone` button (`chat-picker-invite-empty`; new ARB key `chatPickerInviteButton` en+pl) — a lone socket in an empty comb looks broken. `conversations_screen.dart` routes both `ChatPickerInviteNew` and `ChatPickerReviewInvitations` to `InvitationsScreen` (accept/decline stays there per §6 — the picker still never accepts inline).
- **Invitations tab:** section count chips are `HexPill`s; the "Waiting for you" badge flips to `colorScheme.primary` fill while `friendRequests.isNotEmpty` (new `accented` param). One-shot 240 ms fade + 12 px rise entrance when the skeleton hands over (`_InvitationEntrance`, `TweenAnimationBuilder`, reduce-motion → plain child, `alwaysIncludeSemantics: true` — Opacity(0) drops semantics on frame one and broke the semantics test until added).
- **Chat header (`chat_detail_screen.dart`):** both `AvatarCircle`s (embedded 36px, `GlassTopBar` slot 52px) → `HexAvatar`. Supersedes the round-4 "bare 52px circle" Telegram ruling by owner ask.
- **Design review (designer subagent) SHIP-WITH-FIXES; HIGH fixed same session:** `HexAvatar` ringed with `convItemBorder@0.6` is ~1.3:1 on blue (`#2B3B45` on `#1E2D3A`) — the hex outline vanished. All four touched callsites (InvitationRow, search row, both chat headers) now ring with `colors.mutedText`, re-rendered blue+dark to confirm. NOTE: `HexRingPainter` still halves whatever it gets (0.6 alpha); `conversation_tile`'s hexes still pass `convItemBorder` — untouched, worth an owner look on blue.
- **Preview harness (`test/preview/invitations_preview.dart`, NEW):** `?view=inbox|picker|picker-empty|header&theme=…&incoming=N&sent=N&accepted=1` — invitations surfaces render without a backend, same pattern as `contact_network_preview.dart`.

## Key files

`frontend/lib/widgets/hex_pill.dart` (new), `hex_avatar.dart`, `chat_honeycomb_picker.dart`, `contact_network_view.dart`, `invitations/invitation_row.dart`, `invitations/invitation_status_pill.dart`, `frontend/lib/screens/invitations_screen.dart`, `conversations_screen.dart`, `chat_detail_screen.dart`, `frontend/lib/l10n/app_en.arb`+`app_pl.arb`, `frontend/test/screens/conversations_honeycomb_picker_test.dart` (+2), `frontend/test/preview/invitations_preview.dart` (new).

## Verification

Round 1: `flutter analyze` clean; suite 1198 + 10 skipped (+2 picker tests). Round 2 final: **1203 + 10 skipped, all green** (+3 forge, +2 comb). Visual loop closed via the preview harness + browser screenshots across dark/light/teal/blue (inbox, picker, empty picker, chat header, comb collapsed/expanded, ping lattice); blue re-shot after the contrast fix; the accept→forge flow click-verified end-to-end in the preview after the fake-echo fix (`ab2ef05`).

## Notes for next session

- Branch pushed through `ab2ef05`, owner reviewed in the preview and approved ("all seems good") — NOT merged, no version bump; merge to master is the next step when owner says go.
- Review LOWs deliberately NOT acted on (owner-taste calls): picker accent text uses `colorScheme.primary` on glass (SPEC suggests `onGlassAccent`; pre-existing); "Pending" labels both directions; accepted-ready card stacks three accent elements; SPEC §10 "no title pills" contradicts the shipped app (doc drift, app-wide, predates this).
- Chat-header hex is ~45px wide at 52px height vs the 52px back-circle — slight mass asymmetry; owner to judge on device.
- Trap re-confirmed: the `edit` tool's auto-repair silently swallowed a `Transform.translate(offset:)` argument — re-read after any repaired hunk.
- Preview harness traps: without a socket the provider's accept/decline only set inFlight and emit into the void — the harness fakes the server echo after 400 ms; cast emitted payloads as bare `Map` (inferred-type literals make `as Map<String, dynamic>` throw, silently, inside the delayed future). And `flutter run -d web-server` hot-restart ('R') silently no-ops once the connected client is stale — cold-restart the process (the documented LATEST trap, paid again).
