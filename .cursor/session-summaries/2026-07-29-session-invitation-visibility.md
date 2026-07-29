# Invitation visibility — pending labels, a door for the `+` badge, named picker hexes, and honeycomb wire routing

**Date:** 2026-07-29

Branch `feat/invitation-visibility`, worktree `C:/Users/Lentach/Desktop/fireplace-wt-invitation`, cut from `origin/master` at `43601bf`. **Not merged, not deployed, no version bump.**

## What was done

Three owner-reported invitation problems, plus one wire-rendering bug the owner spotted mid-session in a screenshot.

### 1. A pending outbound invitation now says "Pending"

The Contacts board's ghost cell (`_buildGhostNode`) carried its state in `Icons.send_outlined` and nothing else — while `_buildGhostSemantics` already announced `"cora, invitation sent"` to screen readers. **The blind user was told; the sighted user got an arrow.** `invitationStatusPending` ("Pending" / "Oczekuje") already existed in both ARBs and was used only by the Invitations screen.

- Ghost cells render the word under the name in `colorScheme.primary`. Measured on every theme's field background: cosmic **12.88:1**, blue 6.33, dark 5.88, light 4.72, teal 5.24 — all past the 4.5:1 text gate.
- `ContactNetworkView` reserves a **two-line `labelHeight` only while `sentInvitees` is non-empty**. Uniform rows are what keeps the lattice a lattice, and the extra ~15px of row height is paid only until the last invitation resolves. The re-flow on invitee change was already handled (`inviteesChanged` → `_armedThroughRow` reset).
- New injected params `pendingInviteLabel` / `pendingInviteSemanticLabel`; the view stays l10n-free by contract. The hardcoded English `'$name, invitation sent'` semantics string is gone — it now uses `invitationSemanticOutgoing`.

### 2. The `+` badge has a door

`conversations_screen.dart` badged the `+` with `pendingRequestsCount`, but `onPressed` opened a friends-only picker. `InvitationsScreen` was reachable from **exactly one** place in the app: Contacts → add cell / inbound port.

- `showChatHoneycombPicker` returns `ChatPickerChoice` (`ChatPickerFriend` | `ChatPickerReviewInvitations`) instead of `UserModel?`.
- Senders of `friendRequests` **lead the comb** as accent terminals (`HexAvatar(ember: 1, borderColor: primary)` + the `Pending` caption), and the sheet gains an accent subtitle line reusing `contactNetworkPendingRequests(n)` — "2 friend requests waiting".
- Tapping one pops the sheet and pushes `InvitationsScreen`; its `int?` result (peer id from `Open chat`) routes into the existing start-chat path.
- **The picker never accepts inline.** Accept/decline own the scoped-failure + retry state machine hardened in #106; a second copy would drift.
- Badge divergence checked and dismissed: `chat-friend-request.service.ts:525/:622` re-emits `pendingRequestsCount` to the acting client after both accept and decline, so the count is server truth and needs no client-side fixup.

### 3. Picker hexes are named

`_HoneycombFriendGrid` was avatar-only — which collapses to a single initial for anyone without a photo. Now hex + 11px `w600` ellipsized name, mirroring the Contacts board. Rows stopped overlapping (`hexHeight + labelGap + labelHeight + rowGap`); the half-cell odd-row stagger is what still reads as a comb.

### 4. Wires no longer cut through hexes (owner-reported, pre-existing)

The owner circled the feeds slicing the corners off Ada and Borys. Reproduced at `invites=0`, so **not** caused by the row-pitch change.

Root cause: `ContactHexLayout.routePath` did its sideways travel **across the row plane**. A pointy-top lattice has no straight vertical channel *and* no clean long diagonal — a wide row's gaps sit exactly over the narrow row's centres — so any monotone diagonal is inside a hex every other row.

Now: vertical travel only inside a gap corridor (pitch/2 from either centre, ~17px past the hex's widest point); sideways travel only in the empty band between rows; the rim fan is per **corridor** (≤ `columnsWide + 1` rays), never per contact. Gap-selection ties break **outward** so a mirrored pair of contacts weaves as a mirror image.

**A horizontal-rail variant was built first and rejected by the owner** ("it cannot be horizontal lines, it must be like previous"). Do not reintroduce it. Rendered clean at 8 / 40 / **200** nodes.

### Drive-by

- The `+` badge's hardcoded `Colors.red` / `Colors.white` → `colorScheme.error` / `onError` (playbook §1: never invent values).
- `_measureHeight` (both combs) now measures `DefaultTextStyle.of(context).style.merge(style)`. `Text` merges into the ambient default, which carries a line height the bare style omits; the bare measurement under-reports ~4px per line. At one line that hid inside the board's 9px row slack — at two lines it overflowed the caption box (caught as a real `RenderFlex overflowed by 4.0 pixels`).
- Preview harnesses: `contact_network_preview.dart` gained `&invites=N`; `glass_preview.dart` seeds friends so the `+` picker is reviewable.
- **Zero new ARB keys** — `invitationStatusPending`, `invitationSemanticIncoming`, `invitationSemanticOutgoing` and `contactNetworkPendingRequests` all already existed. No `flutter gen-l10n` run needed.

## Key files

| File | Change |
|---|---|
| `frontend/lib/widgets/contact_network_view.dart` | pending caption + 2-line label budget, merged-style measurement, Manhattan-in-corridors route, `_nearestGap` outward tie-break |
| `frontend/lib/widgets/chat_honeycomb_picker.dart` | rewritten: `ChatPickerChoice`, invitation terminals, captions under every hex |
| `frontend/lib/screens/conversations_screen.dart` | picker result switch, `_openInvitations`, `_startChatWith`, badge tokens |
| `frontend/lib/screens/contacts_screen.dart` | injects `pendingInviteLabel` / `pendingInviteSemanticLabel` |
| `frontend/test/screens/conversations_honeycomb_picker_test.dart` | +3 tests (captions, invitation terminal → queue, no-invite case) |
| `frontend/test/widgets/contact_network_view_test.dart` | asserts the visible `Pending` word |
| `frontend/test/preview/*.dart` | `&invites=N`, seeded friends |
| `frontend/CLAUDE.md` §6, root `CLAUDE.md` §3 | contracts + test count 1071 → 1074 |

## Verification

- `flutter analyze --no-fatal-infos` — **No issues found**.
- `flutter test` — **1074 passed, 5 skipped** (226 s).
- `node scripts/verify-claude-frontend-test-counts.mjs` — **OK: CLAUDE.md matches flutter test (1074 tests, 5 skipped)**.
- **Fail-before proven three ways:** stashing `frontend/lib` failed both new picker tests; `sed`-ing `if (widget.pendingInviteLabel != null)` → `if (false)` failed the ghost test with `Found 0 widgets with text "Pending"`.
- **Rendered** (playbook §0): Contacts board with 3 pending invites in **all five themes** (cosmic/blue/dark/light/teal); wire routing at 8 / 40 / 200 nodes; the `+` picker sheet in light / cosmic / teal.

## Notes for next session

- **Not merged, not deployed.** Needs owner OK per root §1, then a PATCH bump on master before `deploy-web.ps1`.
- **Device check worth doing:** the picker sheet is taller now (captions ended the row overlap). On a short phone with many friends it scrolls sooner — `maxHeight` is still `0.68 * screenHeight`.
- Friend hexes in the picker still use `glass.border`, which is a near-invisible hairline on the light themes — the same trap `_HexChromePainter` documents for the Contacts board (it uses `onSurface` instead). Left alone deliberately: not asked, and the new captions now carry identification. Worth a ruling if the owner notices.
- The picker has **no search field**. Captions fix identification up to ~20 friends; past that, search is the next step.
- Row-0 feeds still pass behind the `LOCAL NODE` caption for centre corridors. Unavoidable without moving the caption — the widget paints over the hairline.
- Preview servers: `flutter run -d web-server -t test/preview/contact_network_preview.dart` (`?screen=1&count=N&invites=N&theme=…`) and `-t test/preview/glass_preview.dart` (`?screen=desktop&theme=…`, click the `+` at ~355,40 in a 390px viewport). On Windows a supervised `flutter` needs `cmd.exe /c flutter.bat …`.
