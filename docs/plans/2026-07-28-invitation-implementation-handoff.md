# Invitation Rework — Fresh Implementation Agent Handoff

Copy everything inside the block into a fresh agent session.

```text
Role: You are the implementation owner for Fireplace's invitation rework. The product direction is approved. Implement it end to end; do not redesign the flow or stop at a scaffold.

WORKTREE AND BRANCH
- Work only in: C:/Users/Lentach/Desktop/fireplace-wt-invitation
- Existing branch: feat/invitation-rework
- Starting pushed head: a8f4192
- Do not work in C:/Users/Lentach/Desktop/fireplace.
- Do not merge to master or deploy without explicit owner approval.

MANDATORY CONTEXT — READ FIRST, IN ORDER
1. C:/Users/Lentach/Desktop/fireplace-wt-invitation/CLAUDE.md
2. C:/Users/Lentach/Desktop/fireplace-wt-invitation/frontend/CLAUDE.md
3. C:/Users/Lentach/Desktop/fireplace-wt-invitation/backend/CLAUDE.md
4. C:/Users/Lentach/Desktop/fireplace-wt-invitation/.cursor/session-summaries/LATEST.md
5. C:/Users/Lentach/Desktop/fireplace-wt-invitation/docs/design/flutter-ui-playbook.md
6. C:/Users/Lentach/Desktop/fireplace-wt-invitation/docs/design/liquid-glass/SPEC.md
7. C:/Users/Lentach/Desktop/fireplace-wt-invitation/docs/plans/2026-07-28-invitation-flow-research.md
8. C:/Users/Lentach/Desktop/fireplace-wt-invitation/docs/plans/2026-07-28-invitation-flow-rework.md

Use the planning-with-files skill because this is cross-tier, multi-step work. Use the flutter-frontend-design skill before touching the invitation UI. Follow the repository's required session-summary, test-count, branch, commit, and push rules.

PRODUCT OUTCOME
Build one sharp, coherent Invitations relationship inbox. A sender must see pending invitations after sending. Accepting must create or find the conversation and show “Invitation accepted · Chat ready,” but must never redirect automatically. Chat opens only after an explicit Open chat tap.

CURRENT BEHAVIOR ALREADY PROVEN
- Backend already persists outgoing pending requests and emits sentRequestsList.
- FriendsProvider already stores friendRequests, sentRequests, and pendingRequestsCount.
- Contacts renders outgoing recipients only as muted ghost terminals.
- AddOrInvitationsScreen renders inbound requests only.
- Exact search auto-sends; friendRequestSent shows a snackbar and pops the screen.
- Accept shows Friend added optimistically before server confirmation.
- Normal acceptance emits openConversation to the accepter.
- Reciprocal/mutual auto-accept also emits openConversation to the caller.
- The invitation screen consumes openConversation and returns the id; Contacts then opens chat.
- Friendship acceptance is currently critical, but conversation findOrCreate is non-critical. Partial success is real and must be represented honestly.
- Frontend rule: never call getConversations/getFriends inside onFriendRequestAccepted; it causes stale-snapshot races.

PRIMARY TARGETS TO INSPECT BEFORE EDITING
Backend:
- backend/src/chat/services/chat-friend-request.service.ts
- backend/src/chat/services/chat-friend-request.service.spec.ts
- backend/src/friends/friends.service.ts
- backend/src/chat/chat.gateway.ts
- backend/src/chat/mappers/friend-request.mapper.ts or the actual mapper path found in source
- relevant DTOs and E2E wire harness events

Frontend:
- frontend/lib/screens/add_or_invitations_screen.dart
- frontend/lib/screens/contacts_screen.dart
- frontend/lib/screens/conversations_screen.dart
- frontend/lib/screens/main_shell.dart
- frontend/lib/providers/friends_provider.dart
- frontend/lib/providers/conversations_provider.dart
- frontend/lib/providers/connection_provider.dart
- frontend/lib/models/friend_request_model.dart
- frontend/lib/widgets/contact_network_view.dart
- frontend/lib/widgets/top_snackbar.dart
- frontend/lib/l10n/app_en.arb and app_pl.arb
- frontend/test/screens/add_or_invitations_test.dart
- frontend/test/providers/friends_provider_test.dart
- frontend/test/widgets/contact_network_view_test.dart
- frontend/test/preview/glass_preview.dart

Use grep/LSP to find every event listener, emitter, pending-open consumer, localization key, test, and callsite before changing exported symbols or wire payloads. Code wins over this handoff if a path or symbol moved.

APPROVED UX
One pushed utility screen titled Invitations:
- Shared Fireplace floating utility chrome.
- Compact invite-by-handle control.
- Waiting for you section for incoming invitations.
- Sent section for outgoing pending invitations.
- No Add User / Friend Requests tabs.
- Keep the Contacts honeycomb ghost nodes as ambient summary, not the sole proof of an outgoing request.

SEND FLOW
1. User searches username#tag.
2. Show an identity result with avatar/hex, full handle, and Send invitation.
3. Do not auto-send merely because one exact result exists.
4. On tap, keep the result in place with action-level progress.
5. Only after authoritative server success, show the person at the top of Sent with Waiting for response.
6. Keep the Invitations screen open; do not pop.
7. On failure, preserve the handle/result and show a scoped error. Never show false success.
8. Reconnect/refresh must restore outgoing pending invitations from server state.

INCOMING / ACCEPT FLOW
Incoming row:
- Real avatar/hex consistent with Contacts.
- Full display handle.
- “Wants to connect.”
- Primary Accept action.
- Quiet secondary Decline action.

On Accept:
1. Keep the row mounted; disable row actions and show progress inside Accept.
2. Wait for authoritative backend confirmation.
3. Backend accepts friendship and creates/finds the conversation.
4. Transform the row to:
   - Invitation accepted
   - Chat ready
   - Open chat
   - Done
5. Stay on Invitations until the user chooses.
6. Open chat is the only action that may navigate.

PARTIAL SUCCESS
If friendship succeeds but conversation setup fails:
- Show Invitation accepted.
- Show Chat setup needs retry.
- Offer Create chat or Retry.
- Do not claim Chat ready.
- Retrying must be idempotent and use the existing friendship/start-conversation validation path where appropriate.

SENDER ACCEPTED EXPERIENCE
- The authoritative accepted outcome, including nullable conversationId/chat readiness, must be emitted to BOTH sender and accepter.
- If sender is on Invitations, the outgoing row can transform into accepted/chat-ready state.
- Elsewhere, show “<name> accepted your invitation” with an optional Open chat action.
- The conversation appears in Chats.
- Never auto-open it.

RECIPROCAL INVITATIONS
Keep mutual-request auto-accept, but remove its automatic navigation. It must produce the same accepted/chat-ready outcome and explicit Open chat action.

WIRE CONTRACT
- Remove acceptance-driven openConversation from normal accept and reciprocal-auto-accept flows.
- Reserve openConversation for explicit startConversation requests.
- Emit the accepted relationship result to both users only after the conversation create/find attempt.
- Carry conversationId as nullable and chatReady as an explicit or derivable result.
- Reuse mapper/DTO conventions; do not duplicate user/request mapping.
- Add a request-scoped failure result or Socket.IO acknowledgement containing requestId, action, and stable reason. A global error cannot safely clear the correct row if multiple actions exist.
- Keep refreshed conversations, friends, incoming requests, sent requests, and counts.
- Do not add client refetches in onFriendRequestAccepted.
- Do not navigate from FriendsProvider. Use the project's pending-consume/explicit-intent pattern.

A conceptual accepted shape is:
{
  request: <friend request payload>,
  conversationId: 123 | null,
  chatReady: true | false
}
Choose the smallest compatible shape after inspecting current payload mapping and tests.

FRONTEND STATE CONTRACT
Keep invitation complexity behind a small Friends/Invitation interface. State must cover:
- incoming requests;
- outgoing pending requests;
- send/accept/decline in-flight status scoped by user/request;
- server-confirmed accepted/declined/send outcomes;
- conversationId when ready;
- accepted-but-chat-not-ready recovery;
- consume/clear behavior for one-time global feedback.

Do not create a second parallel state convention beside existing providers. Deepen FriendsProvider or an existing part/seam unless code proves a separate module is necessary.

VISUAL DIRECTION
The screen must look native to Fireplace, not stock Material:
- Glass only on floating chrome; content rows stay opaque.
- Replace bulky tab chrome with the shared utility header.
- Reuse Contacts identity grammar: real hex/avatar inbound, dashed/send ghost outbound.
- Compact section labels, count, identity, one status line, and actions.
- Solid mini-pills for Pending, Accepted, and Chat ready; never glass.
- Accept is the single primary accent action. Decline is quiet. Do not use equal-weight hardcoded green/red buttons.
- Theme tokens only: RpgTheme, FireplaceColors, GlassTheme. No hardcoded screen colors or new font families.
- Compact empty lines such as Nothing waiting for you / No sent invitations; no giant 64px empty icon.
- First-load skeleton rows; action-local progress; no screen-level spinner.
- One 180–220 ms row state transition, played once and disabled when MediaQuery.disableAnimationsOf(context) is true.
- No animation on the chat-entry route; keep instantOpaqueRoute.
- Accessibility must announce direction, person, state, and action progress.
- Desktop: close invitation surface and select/open the conversation pane only after explicit Open chat.
- Mobile: close invitation surface and use the existing instant opaque chat route only after explicit Open chat.

TERMINOLOGY / LOCALIZATION
Use one user-facing vocabulary consistently in English and Polish:
- Invitations
- Waiting for you
- Sent
- Send invitation
- Waiting for response
- Wants to connect
- Invitation accepted
- Chat ready
- Open chat
- Done
- Chat setup needs retry
- Decline

Use ARB keys and regenerate localization output with the repository's existing process. Internal FriendRequest names may remain if a cross-tier rename adds no user value; do not perform a cosmetic domain-wide rename.

NON-GOALS
- Do not implement Withdraw invitation unless the owner explicitly adds it. There is no sender-authorized cancel operation today.
- Do not add message content before friendship.
- Do not turn invitations into faux chat previews.
- Do not add dependencies unless existing code makes one necessary.
- Do not redesign Contacts, Chats, navigation, or the global theme beyond what this flow requires.
- Do not add migrations unless source inspection proves a schema change is unavoidable; the approved design should not require one.
- Do not merge or deploy.

TEST-FIRST CONTRACTS / REQUIRED REGRESSIONS
Backend focused tests must prove:
- normal accept creates/finds conversation;
- accepted payload with conversationId reaches accepter and online sender;
- normal accept does NOT emit openConversation;
- reciprocal auto-accept produces the same accepted payload for both sides and does NOT emit openConversation;
- conversation setup failure emits accepted-but-not-ready honestly;
- scoped action failure contains enough identity to clear the correct in-flight row;
- sent/incoming/friends/conversation list refresh behavior remains intact.

Frontend provider/widget tests must prove:
- sentRequestsList renders under Sent after send and survives reload/reconnect state;
- send no longer pops the screen;
- one-result search does not auto-send;
- Accept waits for server confirmation;
- Accept does not navigate automatically;
- accepted-ready row shows Open chat;
- only tapping Open chat navigates to the correct conversation;
- sender accepted feedback can open the correct conversation explicitly;
- accepted-but-not-ready shows retry, not Chat ready;
- reciprocal acceptance does not navigate;
- reduce-motion disables row travel;
- semantics distinguish incoming/outgoing/status.

Cross-tier E2E:
- Update the real Socket.IO wire harness for the changed accepted payload/event order.
- Remember EventLog.discard immediately before every state-transition assertion; existing history says otherwise empty-list assertions can pass vacuously.
- Run the local real-backend test_e2e flow because this is a shared wire-contract change.

VISUAL VERIFICATION — REQUIRED, NOT OPTIONAL
After focused tests are green:
1. Add/update a preview fixture that shows: inbound row, outbound pending row, accepted/chat-ready row, and accepted/chat-not-ready row.
2. Run Flutter web preview as a background process; do not wait on flutter run to exit.
3. Ask the owner before opening the browser tool because it opens a visible window on this workstation.
4. Capture and inspect phone and desktop widths in blue, dark, light, and teal themes.
5. Compare against docs/design/liquid-glass/after/*.png and SPEC.md.
6. Iterate on spacing, hierarchy, contrast, alignment, hover/focus, and empty/loading states.
7. Run the playbook's read-only design-review checkpoint against the captured screenshots.
8. Stop/cancel the render server during cleanup.

VERIFICATION BEFORE COMMIT / PR
- Run focused backend tests while iterating.
- Run focused frontend test files/directories while iterating; never pass a long explicit file list to flutter test.
- Run backend full suite: cd backend && npm test
- Run backend build if required by changed TS contracts: cd backend && npm run build
- Run frontend analysis: cd frontend && flutter analyze --no-fatal-infos
- Run frontend full suite: cd frontend && flutter test
- Run full-stack wire harness against live local backend/Postgres: cd frontend && flutter test test_e2e
- Update documented test counts if tests were added, then run both count-verifier scripts required by CLAUDE.md.
- Run node scripts/impact.mjs as the repository impact hint, but do not treat it as coverage.
- Fix every regression caused by the change.

DONE MEANS ALL OF THESE ARE OBSERVED
1. Sending leaves Invitations open and shows the recipient under Sent.
2. Refresh/reconnect restores pending outgoing invitations.
3. Send/accept/decline success appears only after authoritative confirmation.
4. Accept creates/finds a conversation but never navigates.
5. Reciprocal auto-accept never navigates.
6. Both sender and accepter receive conversationId or an honest not-ready outcome.
7. Open chat opens the correct conversation on mobile and desktop.
8. Partial friendship/chat failure is recoverable and never mislabeled Chat ready.
9. UI matches Fireplace in all four themes and both target widths.
10. Focused, full-tier, and real-wire verification is green.
11. Required session summaries are updated.
12. Changes are committed and pushed on feat/invitation-rework. Do not merge or deploy.

REPORT BACK WITH
- Exact files changed.
- Final wire payload/event ordering.
- Exact user-visible flow for sender, accepter, reciprocal request, and partial failure.
- Screenshots/visual critique outcome for all themes and widths.
- Exact test/analyze/build/E2E commands and observed results.
- Commit hash and pushed branch.
- Any remaining blocker stated plainly; do not call incomplete work done.
```
