# Invitation visibility — pending labels, a door for the `+` badge, named picker hexes, and honeycomb wire routing

**Date:** 2026-07-29

**RELEASED 0.0.138 / `bf80602`, FRONTEND ONLY, smoke 5/5.** PR **#110** merged as `ce1ab79`; bump in `bf80602`; CI green on both master commits before deploying. Backend untouched — `/version` stays `0.0.136 / 6fb36bf` BY DESIGN.

Built on branch `feat/invitation-visibility` in worktree `C:/Users/Lentach/Desktop/fireplace-wt-invitation`, cut from `43601bf`, rebased onto `5c8e31d`.

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
| `frontend/lib/utils/caption_metrics.dart` | **new** — shared `measureCaptionHeight`, does the `DefaultTextStyle` merge itself |
| `frontend/CLAUDE.md` §6, root `CLAUDE.md` §3 | contracts + test count 1071 → 1075 |

## Verification

- `flutter analyze --no-fatal-infos` — **No issues found**.
- `flutter test` — **1075 passed, 5 skipped** (149 s), after the review round.
- `node scripts/verify-claude-frontend-test-counts.mjs` — **OK** (1075 tests, 5 skipped).
- **Fail-before proven four ways:** stashing `frontend/lib` failed both new picker tests; `sed`-ing `if (widget.pendingInviteLabel != null)` → `if (false)` failed the ghost test with `Found 0 widgets with text "Pending"`; re-latching the entrance guard left the picker at 0.637 opacity.
- **Rendered** (playbook §0): Contacts board with 3 pending invites in **all five themes** (cosmic/blue/dark/light/teal); wire routing at 8 / 40 / 200 nodes; the `+` picker sheet in light / cosmic / teal.

## Review round (two-axis, parallel `reviewer` sub-agents vs `5c8e31d`)

**Spec axis: correct.** R1–R4 all satisfied, every non-goal respected, no version bump. Three minor findings.
**Standards axis: correct.** Zero hard violations; one judgement call.

Three findings actioned:

1. **Reduce-motion regression I introduced (P3, real).** `chat_honeycomb_picker.dart` was whole-file rewritten from a *structural* read, and `didChangeDependencies` was one of the bodies the summary had elided — so it got reconstructed rather than ported. The original checked `MediaQuery.disableAnimationsOf` **first, unguarded**, and latched only the `forward()`; my version hoisted the `_entranceStarted` latch above it, so reduce-motion switched on mid-entrance was ignored (playbook §9). Restored, plus a fail-before-proven regression test (latched version sits at **0.637** opacity instead of 1). The whole file diff was then re-read end to end against `git show 5c8e31d:` — no other drift.
2. **Duplicated caption measurement (judgement call, valid).** The two helpers were byte-identical logic and §6 had just made it a shared contract. Extracted to `utils/caption_metrics.dart` as `measureCaptionHeight(context, style, lines:)`, which now performs the `DefaultTextStyle.merge` **internally** — the merge was the actual trap, so leaving it at the callsites left the bug reintroducible at caller three.
3. **Badge/inviter divergence (P2, conf 0.45) — investigated and dismissed.** `connection_provider.dart:281` calls `getFriendRequests()` on socketReady, and the backend's `handleGetFriendRequests` emits `friendRequestsList` **and** `pendingRequestsCount` from the same handler (`chat-friend-request.service.ts:748-749`). The two fields cannot durably disagree; the window is sub-frame at connect, not a state the user can sit in.

Not actioned, deliberately:

- **On-axis contact leans right (P3, conf 0.4).** For a slot exactly on the core axis, narrow rows offer a genuine tie between `±pitch/2` and `sideSign` resolves it rightward, so that one wire is not mirror-symmetric with itself. Unavoidable: descending straight down at `core.dx` hits a narrow-row hex centre, so the wire *must* pick a side. The alternative — alternating sides by row parity — trades a consistent lean for a zigzag, which reads worse.

## Release

```
/version.json  {"app_name":"fireplace","version":"0.0.138","package_name":"fireplace","gitCommit":"bf80602"}
/version       {"version":"0.0.136","gitCommit":"6fb36bf","buildTime":"2026-07-28T23:42:50Z"}
/health        {"status":"ok","db":"ok"}
```

`deploy-web.ps1`'s own stale-build gate passed 5/5 (health, both version surfaces, `main.dart.js` literally containing `bf80602`, and an app boot in a fresh headless browser), then re-confirmed independently by curl.

**The deploy ran from the WORKTREE, not the main checkout — and that mattered.** `deploy-web.ps1` sets `$repo = Split-Path -Parent $MyInvocation.MyCommand.Path` and `Set-Location $repo`, so it builds whatever checkout the SCRIPT file lives in. The main copy `C:/Users/Lentach/Desktop/Fireplace` is on the owner's `feature/android-encrypted-store` with untracked WIP under `frontend/lib/services/encryption/`; invoking `…/fireplace/deploy-web.ps1` would have built and shipped that branch. The gitignored `deploy-web.config.ps1` already existed in the worktree, byte-identical (same md5), so the worktree copy ran with the correct VM target and Giphy key.

## Notes for next session

- **Owner must fully close + reopen the PWA** → Settings footer `0.0.138 · bf80602`. **Never uninstall or clear site data** (destroys local E2E Signal keys).
- **`fireplace-wt-invitation` is now the only checkout on `master`** (at `bf80602`) and was deliberately NOT removed: the main working copy is on the owner's Android branch, so removing it would leave the repo with no master checkout. The merged branch `feat/invitation-visibility` is deleted locally and on the remote.
- **Device check worth doing:** the picker sheet is taller now (captions ended the row overlap). On a short phone with many friends it scrolls sooner — `maxHeight` is still `0.68 * screenHeight`.
- Friend hexes in the picker still use `glass.border`, which is a near-invisible hairline on the light themes — the same trap `_HexChromePainter` documents for the Contacts board (it uses `onSurface` instead). Left alone deliberately: not asked, and the new captions now carry identification. Worth a ruling if the owner notices.
- The picker has **no search field**. Captions fix identification up to ~20 friends; past that, search is the next step.
- Row-0 feeds still pass behind the `LOCAL NODE` caption for centre corridors. Unavoidable without moving the caption — the widget paints over the hairline.
- Preview servers: `flutter run -d web-server -t test/preview/contact_network_preview.dart` (`?screen=1&count=N&invites=N&theme=…`) and `-t test/preview/glass_preview.dart` (`?screen=desktop&theme=…`, click the `+` at ~355,40 in a 390px viewport). On Windows a supervised `flutter` needs `cmd.exe /c flutter.bat …`.
