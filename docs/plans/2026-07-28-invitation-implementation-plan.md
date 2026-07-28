# Invitation Rework — Implementation Plan

**Date:** 2026-07-28
**Worktree:** `C:/Users/Lentach/Desktop/fireplace-wt-invitation`
**Branch:** `feat/invitation-rework` — head at planning time `375099c`
**Status:** plan only; no application source changed yet
**Supersedes nothing.** Approved design: [`2026-07-28-invitation-flow-rework.md`](2026-07-28-invitation-flow-rework.md). Scope lock: [`2026-07-28-invitation-implementation-handoff.md`](2026-07-28-invitation-implementation-handoff.md).

This plan resolves every open design decision the handoff left to "choose after inspecting source". The traces backing each decision are recorded in `.planning/invitation-rework/findings.md` (local, gitignored).

---

## 0. What is actually broken (verified in source, not inherited)

| Defect | Anchor |
|---|---|
| Acceptance navigates the accepter | `backend/src/chat/services/chat-friend-request.service.ts:399-402` emits `openConversation` to the caller |
| Reciprocal auto-accept navigates the caller | same file `:162` |
| Accepted result is emitted **before** the conversation attempt, so it cannot carry readiness | `:317` / `:321` fire at step 2; `findOrCreate` runs at `:344` |
| Sender never learns the conversation id | accepted payload is `FriendRequestMapper.toPayload` only — `{id,sender,receiver,status,createdAt,respondedAt}` |
| Failures are unroutable | every friend handler emits a global `client.emit('error',{message})` (`:186,194,198,208,227,295,328,418`). No `requestId`, no action, no socket acks anywhere in the gateway, no `WsException`/exception filter in the whole backend |
| Search auto-sends on a single exact match | `frontend/lib/screens/add_or_invitations_screen.dart:246-265` |
| Send pops the screen | same file `:237-244` |
| Accept claims success before the server answers | same file `:513-529` (green `friendAdded` snackbar inside the tap callback) |
| Outbound invitations are invisible except as ghost hexes | `sentRequests` is consumed only by `contacts_screen.dart:305-307` → `ContactNetworkView.sentInvitees` |

Non-defect, already correct and must be preserved: `FriendsService.getSentRequests`, the `sentRequestsList` event, `FriendsProvider._sentRequests`, and the no-refetch rule in `onFriendRequestAccepted` (`friends_provider.dart:100-102`).

---

## 1. Locked contracts

These are decided. Implementation follows them; it does not re-litigate them.

### 1.1 `friendRequestAccepted` becomes the authoritative accepted result — flat, additive

```ts
// built at the emit site, NOT inside FriendRequestMapper
{
  ...FriendRequestMapper.toPayload(friendRequest), // id, sender, receiver, status, createdAt, respondedAt
  conversationId: number | null,
  chatReady: boolean,   // === (conversationId !== null)
}
```

**Flat, not nested `{request, conversationId, chatReady}`.** Reason, in order of weight:

1. **Stale-PWA safety.** Backend deploys independently of the web bundle; already-loaded clients keep running the old code. Nested breaks `FriendRequestModel.fromJson` (`json['id'] as int` on a payload that has no top-level `id`) → a cast throw on *every* acceptance for every stale client. Flat degrades to "old client ignores two unknown keys".
2. `FriendRequestMapper.toPayload` is shared by `friendRequestsList`, `sentRequestsList`, `newFriendRequest`, `friendRequestSent`, `friendRequestRejected`. Adding fields inside the mapper would leak accept-result fields onto five unrelated events; building the accepted payload at the emit site keeps the mapper pure.
3. `test_e2e` reads `request['id']` off this payload today; flat keeps the harness edit small and honest.

`chatReady` is redundant with `conversationId != null` but is emitted explicitly so the client never has to infer product meaning from a null.

### 1.2 The accepted result is emitted **after `conversationsList`, before the request lists**

New order in `handleAcceptFriendRequest`:

1. validate DTO → on failure `friendRequestFailed`, return
2. `friendsService.acceptRequest` (**critical**) → on failure `friendRequestFailed`, return
3. `conversationsService.findOrCreate` (**non-critical**, try/catch, may leave `conversation = null`)
4. `emitConversationsListToBoth`
5. **`friendRequestAccepted` (accepted payload) → caller AND sender if online**
6. `friendRequestsList` + `sentRequestsList` (caller), `sentRequestsList` (sender if online), `pendingRequestsCount` (caller)
7. `emitFriendsListToBoth`
8. **no `openConversation`**

`emitAutoAcceptFlow` mirrors it: `findOrCreate` → `conversationsList(both)` → **`friendRequestAccepted` (accepted payload) to caller AND recipient** → `friendsList(both)` → `sentRequestsList(both)` → `pendingCount(both)` → **no `openConversation`**.

Two constraints pin this slot, and only this slot satisfies both:

- **After `conversationsList`.** Every client that reacts to the accepted result already holds the conversation, so `Open chat` resolves locally. That is what lets us honor the documented ban on refetching inside `onFriendRequestAccepted` (`frontend/CLAUDE.md` §6) without a race.
- **Before `friendRequestsList` / `sentRequestsList`.** Those lists no longer contain the accepted request. If they land first, the provider replaces the pending list and the acting row **unmounts**, then re-mounts a frame later as an accepted row — a visible flicker that breaks the keep-the-row-mounted UX on both sides (`Waiting for you` for the accepter, `Sent` for the sender). Emitting the accepted result first makes the provider swap pending → outcome in one notification, and the later list replacement is a no-op for that row.

`friendsList` and the counts are needed by neither the row nor `Open chat`, so they stay at the end.

### 1.3 New event `friendRequestFailed` — scoped, modeled on `editMessageFailed`

```ts
{
  action: 'send' | 'accept' | 'reject' | 'ensure_chat',
  requestId: number | null,      // set for accept/reject
  recipientId: number | null,    // set for send; the peer id for ensure_chat
  reason: 'invalid_payload' | 'user_not_found' | 'self_request' | 'blocked'
        | 'already_friends' | 'duplicate_request' | 'accept_failed' | 'reject_failed',
}
```

Root `CLAUDE.md` §7 already documents `editMessageFailed` with stable reason strings — this follows that precedent rather than inventing a socket-ack mechanism the gateway does not have (no `@SubscribeMessage` handler in this codebase returns an ack; verified).

**Clean cutover:** the eight `client.emit('error', …)` calls inside `handleSendFriendRequest` / `handleAcceptFriendRequest` / `handleRejectFriendRequest` are **replaced**, not duplicated. `handleUnfriend` (`:504,:517`) and every other handler keep `error` — out of scope.
**Stated tradeoff:** during a backend-ahead-of-frontend window, a stale client loses the generic toast on a friend-request failure. No false success, no data loss. Accepted deliberately; a dual-emit shim would rot.

### 1.4 No schema change, no migration, no new dependency

`friend_requests` already carries everything needed. `findOrCreate` returns `Promise<Conversation>` and **never returns null** — it throws on total failure (`backend/src/conversations/conversations.service.ts:19`). The nullable `conversationId` on the wire comes from the caller's try/catch, not from the service.

### 1.5 Frontend state lives in `FriendsProvider` — no parallel module

New value types in `frontend/lib/models/invitation_state.dart`:

```dart
enum InvitationAction { send, accept, decline }
enum InvitationActionStatus { inFlight, failed }
enum InvitationDirection { incoming, outgoing }
class InvitationOutcome {          // accepted result, survives the request leaving both pending lists
  final int peerUserId;            // IDENTITY — see §1.5.1. Map key, row key, retry key.
  final InvitationDirection direction; // which section the row must stay in
  final UserModel peer;
  final int? requestId;            // display/debug only; NEVER an identity (nullable, may be a row this client never saw)
  final int? conversationId;
  final bool chatReady;
}
class InvitationFailure {
  final InvitationAction action;
  final int? requestId;
  final int? recipientId;
  final String reason;
}
```

`FriendRequestModel` is **not** touched. `conversationId`/`chatReady` are read off the raw map inside `FriendsProvider.onFriendRequestAccepted`; the model stays a pure relationship record used by five other events.

### 1.5.1 Invitation identity is the **peer user id**, never the request id

This is not a style preference; the request id is provably not stable across the reciprocal path.

`FriendsService.sendRequest` (`backend/src/friends/friends.service.ts:91-119`) does **not** reuse the reverse pending row when both users have invited each other. It creates a brand-new row, marks **both** rows `ACCEPTED`, and returns the **new** one:

```ts
const newRequest = manager.create(FriendRequest, { sender, receiver, status: PENDING });
await manager.save(FriendRequest, newRequest);
if (reversePending) {
  await manager.update(FriendRequest, { id: reversePending.id }, { status: ACCEPTED, … });
  await manager.update(FriendRequest, { id: newRequest.id },     { status: ACCEPTED, … });
  return await manager.findOne(FriendRequest, { where: { id: newRequest.id }, … })!;  // ← the NEW id
}
```

So in a reciprocal accept the payload carries request `#new`, while the original sender holds `#old` under `Sent` and the second sender holds `#old` under `Waiting for you`. **Neither client has `#new` in any list.** Keying anything on the payload's request id therefore produces, on both sides at once, a stale pending row that is never removed plus a phantom accepted row — and under the §1.2 ordering that state is now *visible*, because the list refresh that used to paper over it arrives afterwards.

The peer user id has none of these problems: it is the same on both sides, in both directions, in both the normal and the reciprocal path. Consequences, all mandatory:

- `_acceptedOutcomes` is keyed by `peerUserId`.
- `onFriendRequestAccepted` removes from `_friendRequests` and `_sentRequests` **by counterpart user id**, not by request id.
- The row `ValueKey` is the peer user id. It dedupes, and it gives an in-place update when a row transforms **within** its section (the normal accept path). It does **not** survive the cross-section move a reciprocal row makes — Flutter remounts across sibling subtrees regardless of key. See the Phase 3 merge rule for the honest scope; the tested guarantee is continuous presence, not element identity.
- The §1.7 retry pair addresses the outcome by `peerUserId` and the *attempt* by a separate client token. A request id on that wire would be a second identity for the same thing, and the wrong one.
- `requestId` survives on `InvitationOutcome` for logs only. `_requestActions` (accept/decline in flight) stays keyed by request id because it legitimately addresses an inbound row this client holds — but it is **cleared by peer**, not by payload id: the swap collects the request ids of every pending row it removes for that peer, unions `{payload.id}`, and clears all of them. Clearing only `payload.id` leaves the second sender's `Accept` spinner on `#old` running forever after a reciprocal accept.

**Direction precedence (order matters, and this exact order is load-bearing):**

1. `_sendActions[peerUserId]` is in flight → `outgoing`.
2. else peer matches a row in `_friendRequests` → `incoming`.
3. else peer matches a row in `_sentRequests` → `outgoing`.
4. else (invitation arrived while the screen was closed) → fall back to the payload's sender/receiver role.

Rule 1 must come first precisely because the reciprocal case satisfies rules 1 and 2 simultaneously: the second sender holds `#old` inbound *and* has a send in flight. The locked UX says their accepted row belongs under `Sent` — the last deliberate act was sending an invitation, and that is the control they are watching. Resolving `_friendRequests` first would strand it under `Waiting for you`.

Direction is captured at record time, since the same handler clears both pending lists.

### 1.6 Navigation contract

The invitations screen never pushes a chat route and never calls `startConversation` for navigation.

- `Open chat` → `Navigator.pop(context, peerUserId)`.
- `ContactsScreen._openAddOrInvitations` already does `push<int>(...).then((userId) => _openChatWithContact(context, userId))` (`contacts_screen.dart:286-294`) — unchanged. `_openChatWithContact` already branches desktop (select pane) vs mobile (`instantOpaqueRoute` push) at `:62-88`, so both layouts are covered by existing, tested code.
- Both `consumePendingOpen()` consumers inside the invitation screen (`:231`, `:413`) are **deleted**. With acceptance no longer emitting `openConversation`, nothing can fire while the screen is open.
- `openConversation` keeps exactly one producer: `handleStartConversation` (`chat-conversation.service.ts:88`).

### 1.7 Partial-success retry does **not** navigate

`Create chat` on an accepted-but-not-ready row must reach `AcceptedReady`, not `Chat`. Reusing `startConversation` is wrong twice over: it answers with `openConversation`, which teleports the user via the Contacts consumer sitting underneath, and any client-side "swallow the next `openConversation`" flag is **uncorrelated** — a concurrent contact tap would have its explicit navigation silently eaten. Do not build that flag.

Instead, add one correlated request/result pair. This is what the handoff means by "retrying must be idempotent and use the existing friendship/start-conversation validation path".

```ts
// client -> server
ensureInvitationChat { peerUserId: number, correlationId: string }
// server -> caller only
invitationChatReady { peerUserId: number, correlationId: string, conversationId: number | null, chatReady: boolean, reason?: string }
```

- `peerUserId` addresses the **outcome** (§1.5.1). `correlationId` is a client-generated token addressing **this attempt**, echoed verbatim by the server and never interpreted by it. Because the server reflects it, it is **bounded at the DTO, not merely typed `string`**: `@IsString() @Matches(/^[A-Za-z0-9_-]{1,64}$/)`. The charset restriction matters as much as the length — a reflected value should never be able to carry control characters or markup. The client mints `<sessionNonce>-<monotonicCounter>` (8 hex chars + a per-session counter), so tokens are unique, ordered, and trivially inside the bound.
- Both are needed. Peer alone identifies the row but not the attempt: tap `Create chat`, the first attempt stalls, tap again, the second succeeds and the row reads `Chat ready` — then the first attempt's failure lands and overwrites a fresh success with `Chat setup needs retry`. The client therefore stores the current token on the outcome and **applies a result only when the echoed token is still the current one**; anything else is dropped as a stale attempt.
- Authorization reuses the documented shared gate: `ChatValidationService.validateCanMessage(callerId, peerUserId)` (the same blocked+friendship check `handleStartConversation` uses). A caller who is not actually a friend gets `chatReady: false, reason: 'not_friends'`.
- Then `conversationsService.findOrCreate` — idempotent by construction — followed by `emitConversationsListToBoth` so the conversation lands in both lists, then `invitationChatReady` to the caller.
- **No `openConversation` is emitted on this path.** Nothing navigates. The client applies the result to the outcome and the row flips to `Chat ready`, where an explicit `Open chat` tap still has to happen.
- `ConversationsProvider` is **not** modified at all — no `autoOpen` parameter, no suppression state.

Handler lives in `ChatFriendRequestService` next to the accept path (it is an invitation outcome, not a conversation-start intent), with a `@SubscribeMessage('ensureInvitationChat')` in `chat.gateway.ts` throttled like the other mutating friend actions (30/900000) and an `EnsureInvitationChatDto` (`peerUserId: @IsInt() @IsPositive()`, `correlationId` as bounded above) validated through `validateDto`, matching backend `CLAUDE.md` §12. A DTO rejection emits `friendRequestFailed {action:'ensure_chat', recipientId: null, reason:'invalid_payload'}` and nothing else — an unvalidated token must never reach an emit.

---

## 2. Phases

Phases 1–4 are independent given the contracts in §1 and are the parallel batch. Phase 5 depends on 1+2. Phases 6–8 are serial and mine.

### Phase 1 — Backend accepted result and scoped failures

Files: `backend/src/chat/services/chat-friend-request.service.ts`, `.../chat-friend-request.service.spec.ts`, `backend/src/chat/chat.gateway.ts`, a new `EnsureInvitationChatDto` alongside the existing friend-request DTOs.

Test-first. Add/replace in the spec (mocking convention already in the file: `Test.createTestingModule` + `useValue: jest.fn()`, `mockClient = {data:{user:{id:1}}, emit: jest.fn()}`, `mockServer = {to: jest.fn().mockReturnThis(), emit: jest.fn()}`, `onlineUsers = new Map()`):

1. accept emits `friendRequestAccepted` with `conversationId: 100, chatReady: true` to acceptor **and** to the online sender's socket
2. accept emits **no** `openConversation` — replaces the assertion at spec `:146`-style for the accept path
3. accept with `findOrCreate` rejecting emits `conversationId: null, chatReady: false` to both, and still emits every list refresh
4. accept emits `friendRequestAccepted` **after** `conversationsList` and **before** `friendRequestsList` / `sentRequestsList` — assert with `mock.invocationCallOrder`; this is the anti-flicker guarantee from §1.2, so it is a first-class assertion, not a nicety
5. accept failure emits `friendRequestFailed {action:'accept', requestId, reason:'accept_failed'}` and **not** `error` (replaces spec `:226`)
6. auto-accept (mutual) emits the accepted payload with `conversationId` to caller **and** recipient, and **no** `openConversation` (replaces spec `:127`, whose `:146` currently asserts `openConversation`)
7. auto-accept with `findOrCreate` rejecting emits `chatReady: false` to both
8. send failures emit `friendRequestFailed {action:'send', recipientId, reason}` for `self_request`, `blocked`, `user_not_found`, `duplicate_request` (replaces spec `:149`, `:169`, `:189`)
9. reject failure emits `friendRequestFailed {action:'reject', requestId, reason:'reject_failed'}`
10. `ensureInvitationChat` with a real friendship emits `invitationChatReady {peerUserId, correlationId, conversationId, chatReady: true}` to the caller only, emits `conversationsList` to both, and emits **no** `openConversation`
11. `ensureInvitationChat` echoes `peerUserId` and `correlationId` **verbatim** — the server never interprets the token — and a non-friend caller gets `chatReady: false, reason: 'not_friends'` with no conversation created
12. `ensureInvitationChat` is idempotent — called twice with different tokens it returns the same `conversationId` (`findOrCreate` semantics), each echoing its own token
12b. `ensureInvitationChat` **rejects a malformed token before any emit**: a 65-char `correlationId`, one containing `<`/newline/whitespace, a non-string, and a missing/negative `peerUserId` each produce `friendRequestFailed {action:'ensure_chat', reason:'invalid_payload'}` and **no** `invitationChatReady`, **no** `conversationsList`, and no `findOrCreate` call. The server echoes this field, so the bound is a contract, not a formality
13. every existing list-refresh test (`:243`, `:271`, `:317`, `:330`, `:344`, `:361`, `:376`) stays green untouched

Then implement §1.1–§1.3 and the §1.7 handler. `emitAutoAcceptFlow` needs the accepted payload built after `findOrCreate`, so its `payload` parameter becomes the *base* request payload and the accepted emit moves to the slot defined in §1.2.

Acceptance: `cd backend && npx jest chat-friend-request` green; no `openConversation` string remains in `chat-friend-request.service.ts`.

### Phase 2 — Frontend invitation state

Files: `frontend/lib/models/invitation_state.dart` (new), `frontend/lib/providers/friends_provider.dart`, `frontend/lib/providers/connection_provider.dart`, `frontend/lib/services/socket_service.dart` (one emit for `ensureInvitationChat`). `conversations_provider.dart` is **not** touched.

`FriendsProvider` gains:

| Member | Purpose |
|---|---|
| `Map<int, InvitationActionStatus> _requestActions` | accept/decline in flight, keyed by `requestId` |
| `Map<int, InvitationActionStatus> _sendActions` | send in flight, keyed by recipient `userId` |
| `Map<int, InvitationOutcome> _acceptedOutcomes` | accepted rows, keyed by **`peerUserId`** (§1.5.1 — the payload request id is a different row in the reciprocal case) |
| `InvitationFailure? _lastInvitationFailure` + `consumeInvitationFailure()` | one-shot scoped failure |
| `invitationActionFor(requestId)`, `sendActionFor(userId)`, `acceptedOutcomeForPeer(peerUserId)`, `acceptedOutcomesFor(InvitationDirection)` | read surface; the direction-filtered getter is what each section renders |
| `clearAcceptedOutcome(peerUserId)` | the `Done` action |
| `ensureInvitationChat(peerUserId)` / `onInvitationChatReady(data)` | §1.7 retry. The emit mints a fresh `correlationId`, stores it on the outcome as the current attempt token and marks the row retrying; the handler looks the outcome up by `peerUserId` and **applies the result only if the echoed token is still current**, dropping stale attempts |
| `onFriendRequestFailed(data)` | clears the matching in-flight entry, records the failure |
| `_hasIncomingSnapshot` + `_hasSentSnapshot` → `hasLoadedInvitationsOnce` (**both** true) | real fetch signal gating the skeleton. `friendRequestsList` and `sentRequestsList` are two separate socket events (`handleGetFriendRequests` emits them in sequence), so ending the skeleton on the first one flashes a false `No sent invitations` while the second snapshot is still in flight. Each handler sets its own flag; the skeleton ends only when both are set. Both reset on `onConnect(false)` / `clearAll`, **not** on reconnect — data we still hold must not be covered by a skeleton. Playbook §3: never gate a skeleton on a timer |

Behavioral edits:

- `sendFriendRequest` / `acceptFriendRequest` / `rejectFriendRequest` mark in-flight + `notifyListeners()` before emitting.
- `onFriendRequestSent` is the **authoritative send success** and is atomic, same shape as the accepted swap: clear `_sendActions[payload.receiver.id]` **and** insert the payload into `_sentRequests` (dedupe by `requestId`, newest first), then one `notifyListeners()`. Clearing the flag alone is not enough — the backend emits `friendRequestSent` at `:244` and `sentRequestsList` at `:246` as two separate events, so a flag-only handler flips the button back to `Send invitation` with an empty `Sent` section for a frame. The later `sentRequestsList` reconciles authoritatively; the dedupe makes that a no-op. **`_friendRequestJustSent` and `consumeFriendRequestSent()` are deleted** — their only consumer was the pop-after-send block. Grep before deleting.
- `onFriendRequestAccepted` becomes one atomic swap, in this order: resolve the peer (the party that is not `_currentUserId`); resolve `direction` by the §1.5.1 precedence (`_sendActions` first, then `_friendRequests`, then `_sentRequests`, then the payload role); collect every pending row for that peer out of `_friendRequests` and `_sentRequests`; clear `_requestActions` for all of their request ids **plus** `payload.id`; clear `_sendActions[peer.id]`; remove those rows **by peer**, not by request id; insert the `InvitationOutcome` keyed by `peer.id`; then a single `notifyListeners()`. Every one of those "by peer" clauses exists because of §1.5.1: after a reciprocal auto-accept the payload's request id is a brand-new row neither client has ever seen, so any by-id cleanup silently misses and leaves a stale pending row, a stuck `Accept` spinner, and a phantom accepted row side by side. The `_sendActions` clear additionally covers the reciprocal caller, who receives `friendRequestAccepted` and never `friendRequestSent`. **Still no `getConversations()`/`getFriends()`** — the comment at `:100-102` stays and gets a test.
- `onFriendRequestRejected` is the **authoritative decline success** and is the only thing that retires a declined row: clear `_requestActions[requestId]`, remove the id from `_friendRequests`, then one `notifyListeners()`. Until that event lands the row stays mounted with both actions disabled and progress inside `Decline` — the screen never removes a row optimistically, exactly as it never claims `Friend added` optimistically. No `InvitationOutcome` is recorded for a decline; there is nothing to open.
- `_pendingFriendAcceptedByName` widens to a small `PendingFriendAccepted {name, conversationId, chatReady}` so the MainShell toast can offer `Open chat`.
- **Lifecycle is asymmetric, matching the provider's existing reconnect philosophy.** `onConnect(false)` (fresh connect / account switch) and `clearAll` wipe everything: both action maps, `_acceptedOutcomes`, the failure, and both snapshot flags. `onConnect(true)` (reconnect) **preserves `_acceptedOutcomes`** — the server never replays `friendRequestAccepted`, so wiping them on a transient drop permanently destroys an undismissed accepted row and its `Open chat`. What reconnect *does* clear: `_requestActions`, `_sendActions`, `_lastInvitationFailure`, and each outcome's retry token + retrying flag — an action whose result the disconnect swallowed must not leave a spinner running or `Create chat` disabled forever. The snapshot flags also survive reconnect (a skeleton must never cover data we still hold).

`ConversationsProvider`: **unchanged** — the correlated retry in §1.7 removes any need to touch it.
`ConnectionProvider`: register `friendRequestFailed` → `FriendsProvider.onFriendRequestFailed` and `invitationChatReady` → `FriendsProvider.onInvitationChatReady`, adjacent to the friend-event block at `:379-415`.

Tests: extend `frontend/test/providers/friends_provider_test.dart` and add `frontend/test/providers/friends_provider_invitations_test.dart` (raw-JSON-into-handlers convention already used in that file) — in-flight set/clear per action; **the decline round trip**: `rejectFriendRequest` marks in-flight, the row survives until `onFriendRequestRejected` clears the flag and removes it, and `friendRequestFailed{action:'reject'}` clears the flag while leaving the row in place; **the reciprocal round trip, driven exactly as the server produces it** — seed an inbound row `#old` from the peer, call `sendFriendRequest(peer)`, then deliver `friendRequestAccepted` carrying a **different** request id `#new` and no `friendRequestSent`: `_sendActions[peer.id]` clears, the `#old` inbound row is gone, `_requestActions[#old]` is cleared, exactly one outcome exists keyed by `peer.id`, and its `direction` is **`outgoing`** (precedence rule 1 beats the inbound row); **the send round trip**: `onFriendRequestSent` alone puts the row in `sentRequests`, and a following `sentRequestsList` does not duplicate it; **direction** for the plain paths: accepter's seat → `incoming`, sender's seat → `outgoing` (flip `setCurrentUserId`); **the intermediate state immediately after `onFriendRequestAccepted` and before any refreshed list**: `friendRequests` and `sentRequests` both exclude that peer and exactly one outcome exists (asserted from the sender's seat, where the duplicate would appear); outcome recorded with and without `chatReady`; scoped failure clears the right key; sender path records the conversation id; `onFriendRequestAccepted` emits nothing (no refetch); `clearAcceptedOutcome(peer.id)` removes the row; **retry token**: two `ensureInvitationChat` calls for the same peer, then the **first** attempt's `invitationChatReady{chatReady:false}` arriving after the second's success is **dropped** and the row stays `Chat ready`; `hasLoadedInvitationsOnce` stays false after `friendRequestsList` alone and flips only once `sentRequestsList` also lands, resetting on `onConnect(false)`.

Plus the **reconnect** case, which has its own bullet above and its own test: with an undismissed accepted outcome and a `Create chat` attempt in flight, `onConnect(true)` keeps the outcome (still rendering, still offering `Open chat`) while clearing the action maps and the outcome's retry token so `Create chat` is tappable again; `onConnect(false)` clears the outcome too. Assert both directions — a reconnect that drops the outcome and a fresh connect that keeps it are equal and opposite bugs.

### Phase 3 — The Invitations screen

Rename first, with LSP so imports and tests follow: `lib/screens/add_or_invitations_screen.dart` → `lib/screens/invitations_screen.dart`, `AddOrInvitationsScreen` → `InvitationsScreen`. Touched by `contacts_screen.dart:289`, `test/preview/glass_preview.dart:159`, `test/screens/add_or_invitations_test.dart`.

Layout — one scroll view, no `DefaultTabController`, no `TabBar`:

```
Scaffold(extendBodyBehindAppBar: true)
└ Stack
  ├ Positioned.fill → scroll view, top padding = header clearance
  │   ├ invite-by-handle control            (opaque GlassSurface(blur: false))
  │   ├ search result row → Send invitation (action-local progress; NO auto-send)
  │   ├ "Waiting for you"  + count          → incoming rows | "Nothing waiting for you"
  │   └ "Sent"             + count          → outgoing rows | "No sent invitations"
  └ floating chrome: GlassCircle back + GlassPill "Invitations"
```

**Section merge rule.** Each section renders `acceptedOutcomesFor(direction)` first, then that direction's pending rows, so a transformed row stays exactly where the user was looking:

- `Waiting for you` = accepted outcomes with `direction: incoming`, then `FriendsProvider.friendRequests`.
- `Sent` = accepted outcomes with `direction: outgoing`, then `FriendsProvider.sentRequests`.
- Section count = pending + accepted, so the header does not tick down the instant a row is accepted.
- Keys are `ValueKey(peerUserId)` on every row, pending and accepted alike (§1.5.1). Scope the claim honestly: a key preserves element identity only among **siblings under the same parent**, so it gives an in-place update when a row transforms *within* its section (the normal accept path, where direction does not change). In the reciprocal case the row's direction resolves to `outgoing` while its pending row lived under `Waiting for you`, so it moves across section subtrees and Flutter unmounts and remounts it — no key short of a `GlobalKey` changes that, and a `GlobalKey` across two simultaneously mounted subtrees is not worth its failure modes here. **The guarantee we make and test is continuous presence, not element identity:** in every pumped frame there is exactly one row for that peer somewhere on screen. If element state ever genuinely has to survive the move, the fix is to render both sections from one flat keyed list with headers as items — not to sprinkle `GlobalKey`s.
- `Done` (`clearAcceptedOutcome`) is the only thing that removes an accepted row. The pending list has already dropped it server-side, so there is no double render.
- A section shows its one-line empty state only when both of its lists are empty.

The floating `GlassPill`/`GlassCircle` header is hand-rolled, matching the other pushed utility screens (`MainTabScreenHeader` is main-tab-only; there is no shared pushed-utility header widget — confirmed).

New widgets under `lib/widgets/invitations/`:

- `invitation_row.dart` — one widget, five states: `inbound`, `outbound`, `acting`, `acceptedReady`, `acceptedNeedsChat`. Opaque content surface via `GlassSurface(blur: false, shadow: false)` — in this codebase `blur: false` is the documented **tint-only, non-glass tile** (doc comment in `widgets/glass/glass_surface.dart`), which is exactly what the current request cards already use. No blur and no glass effect on any content row. Leading identity element **reuses the avatar widget the Contacts list rows use** (locate in `contacts_screen.dart._buildContactsList`; do not hand-roll a new avatar).
- `invitation_status_pill.dart` — **solid fill, never glass.** A plain `DecoratedBox`/`Container` with a stadium border and an opaque theme-token color: `GlassTheme.opaqueFill` (a solid `Color`, not a translucent glass token) for neutral `Pending`, `colorScheme.primary` for `Accepted` / `Chat ready`, `FireplaceColors.mutedText` for muted label text. **Prohibited in this widget:** `GlassSurface`, `GlassPill`, `GlassCircle`, `BackdropFilter`, and the translucent `GlassTheme.fill` / `GlassTheme.border` tokens. No shared pill widget exists; keep this one scoped to invitations rather than inventing a design-system component with one consumer.

Rules that are non-negotiable here, reconciled against `docs/design/flutter-ui-playbook.md` and `docs/design/liquid-glass/SPEC.md`:

- **Glass grammar (SPEC §1, locked):** glass appears **only** on the floating header — `GlassCircle` back + `GlassPill` title. Every content row, pill, and button surface is opaque. SPEC §10 ("no title pills") is superseded for this surface by SPEC §11, which specifies the add/invitations header as *back circle + title pill + inset tab capsule*; the current screen already renders a `GlassPill` title at `:64`. **The tab capsule is the only part of that header we delete.**
- **Never invent values (playbook §1):** tokens only — `RpgTheme` / `FireplaceColors.of(context)` / `GlassTheme.of(context)`. No `Color(0x…)` in a screen or widget; no new font family. Spacing/radius literals are fine (`8`/`12`/`16`; pill radius 26, card radius 16 per SPEC §5) but must not fight neighbours.
- **Contrast is a gate, not a suggestion (playbook §1, SPEC §8):** the status pill introduces new text-on-surface pairs (label on `colorScheme.primary`, label on `opaqueFill`). Compute WCAG for all four themes and record the ratios; anything under 4.5:1 blocks the phase.
- **Action hierarchy:** `Accept` is the only accent-weight action, `Decline` is quiet text. No hardcoded green/red.
- **Motion (playbook §2):** the row's pending→accepted change is a *state change*, so `Curves.easeInOut` at 200 ms, played once, never re-run on a provider rebuild; any list-entrance uses `easeOut`/`easeOutCubic` 180–280 ms with the stagger capped at the first ~6 rows. All of it forced to `Duration.zero` under `MediaQuery.disableAnimationsOf(context)`. Chat entry stays the zero-duration `instantOpaqueRoute` (banned zone).
- **Loading (playbook §3):** `skeletonizer` rows gated on `hasLoadedInvitationsOnce`, `SolidColorEffect` under reduce-motion, copying `conversation_list_skeleton.dart`. Never a screen-level spinner, never a timer gate.
- Compact one-line empty states, no 64 px icon. `Semantics` announcing direction + person + state.

Deleted behavior: the auto-send block, the pop-after-send block, both `consumePendingOpen` listeners, the optimistic `friendAdded` snackbar, the `Icons.person_add_disabled` empty state, the whole tab scaffold.

Localization — new ARB keys in `app_en.arb` **and** `app_pl.arb`, then `cd frontend && flutter gen-l10n` (generated files are committed):

`invitations`, `invitationsWaitingForYou`, `invitationsSent`, `sendInvitation`, `invitationWaitingForResponse`, `invitationWantsToConnect`, `invitationAccepted`, `invitationChatReady`, `invitationOpenChat`, `invitationDone`, `invitationChatNeedsRetry`, `invitationCreateChat`, `invitationDecline`, `invitationsNothingWaiting`, `invitationsNoneSent`, plus one message per `friendRequestFailed` reason.

Dead keys to remove **only after grepping each for other consumers**: `addInvitations`, `addUser`, `friendRequests`, `friendRequestSentTo`, `addNewUserHint`, `addNewUser`, `noPendingRequests`, `wantsToAddYouAsFriend`, `reject`, `friendAdded`, `requestRejected`.

Widget tests — `frontend/test/screens/invitations_screen_test.dart` replaces `add_or_invitations_test.dart` (whose single test asserts the pending-open pop we are deliberately removing). Harness convention already in that file: `MultiProvider` + `MaterialApp(theme: RpgTheme.themeDataLight, localizationsDelegates, supportedLocales)`.

1. one exact search result does not auto-send
2. tapping `Send invitation` does not pop; the recipient appears under `Sent` on the `friendRequestSent` event alone — assert the intermediate state **before** `sentRequestsList` arrives, then send the list and assert the row is not duplicated
3. `Accept` shows in-row progress and shows no success text before `friendRequestAccepted`
3b. `Decline` keeps the row mounted with both actions disabled and progress inside `Decline`; the row is retired only when `friendRequestRejected` arrives, and never optimistically
4. `friendRequestAccepted` does not navigate; the row becomes `Invitation accepted` · `Chat ready` · `Open chat` · `Done`
5. **accepter role:** the accepted row renders under `Waiting for you`, not under `Sent`
6. **sender role:** the same accepted payload received as the original sender renders under `Sent`, not under `Waiting for you`
7. **no disappearance and no duplicate across the list swap:** drive the real server order — `conversationsList` → `friendRequestAccepted` → `friendRequestsList`/`sentRequestsList` **without** the accepted request — and assert that in every pumped frame there is exactly **one** row for that **peer**, anywhere on screen, on both the accepter and the sender side. Assert presence and count, never element identity (a reciprocal row legitimately moves between section subtrees). This is the widget-level half of §1.2; the backend ordering test is the other half.
8. only `Open chat` pops, and pops the peer `userId`; `Done` removes the row and pops nothing
9. `chatReady: false` renders `Chat setup needs retry` + `Create chat` and never the string `Chat ready`
10. `Create chat` emits `ensureInvitationChat` with a fresh `correlationId` and does not navigate; a matching `invitationChatReady` flips that row — and only that row — to `Chat ready`, while a result echoing a **superseded** token is ignored
11. **reciprocal acceptance, driven as the server produces it:** seed an inbound row from the peer, tap `Send invitation` on that same peer, then deliver `friendRequestAccepted` with a **different** request id and no `friendRequestSent`. Nothing navigates; the `Send invitation` control leaves its progress state; the stale inbound row is gone; there is exactly one row for that peer and it sits under `Sent` with `Open chat`
12. `MediaQuery(data: …disableAnimations: true)` yields a zero-duration transition
13. `Semantics` distinguishes inbound / outbound / status
14. `friendRequestFailed` clears the in-flight row and shows a scoped message — for `action: 'reject'` the row returns to its normal inbound state with both actions re-enabled, not removed

### Phase 4 — Sender-side accepted feedback

Files: `frontend/lib/screens/main_shell.dart:153-165`, `frontend/lib/widgets/top_snackbar.dart`.

The sender toast already exists and is app-wide (`friendAcceptedYourRequest(name)`); it just cannot offer `Open chat` because `showTopSnackBar` wraps its overlay in `IgnorePointer`. Add an optional `onTap` + action label; when `onTap == null` the widget tree stays byte-identical (`IgnorePointer` retained) so no existing toast changes. Tap → `_openChatWithContact`-equivalent using the `conversationId` from the widened `PendingFriendAccepted`. Never auto-open.

Regression: existing top-snackbar tests must stay green; add one asserting the default path is still non-interactive.

**Scope boundary — an OFFLINE sender gets no accepted feedback, and this rework does not change that.** `friendRequestAccepted` is emitted to `onlineUsers.get(senderId)` and nowhere else, on both the accept and the auto-accept path. A sender who was offline when the recipient accepted reconnects into `friendsList` / `conversationsList` / `friendRequestsList` / `sentRequestsList` — all pending-only — so nothing tells them the invitation resolved. They learn it implicitly: the peer is in Contacts and the conversation is in Chats.

This is **pre-existing**, not introduced here: today's `friendRequestAccepted` and `_pendingFriendAcceptedByName` toast are already online-only. Preserving `_acceptedOutcomes` across a reconnect (Phase 2) helps only a client that received the event in the first place — it must not be read as making sender feedback durable.

Closing it properly means a replayable accepted-outcome snapshot: the `friend_requests` rows exist, but "accepted and not yet shown to the sender" is not expressible today, so it needs either a new column (`senderNotifiedAt` → **a migration**, which the non-goals forbid without proof) or a time-window heuristic that will lie in both directions. That is a product decision with a schema cost, so it is **out of scope and stated, not silently absorbed**. If the owner wants it, it is a self-contained follow-up: one column, one connect-time query, one event, one ack.

### Phase 5 — E2E harness and preview fixture

`frontend/test_e2e/full_stack_e2e_test.dart:223-231` and `frontend/test_e2e/stale_otp_epoch_test.dart:111-117` currently obtain the conversation id from bob's auto-open. Rework:

- read `conversationId` off bob's **and** alice's `friendRequestAccepted`, assert they match and `chatReady == true`
- `EventLog.discard('openConversation')` immediately before `acceptFriendRequest`, then assert bob receives **no** `openConversation` within a bounded window — `EventLog` has no negative assertion, so add `EventLog.none(event, within: Duration)` to `test_e2e/support/e2e_test_client.dart`
- keep alice's explicit `startConversation` → `openConversation` assertion; it is now the proof that the reserved use still works
- register `friendRequestFailed` in the client's event list (`e2e_test_client.dart:177-187`)

`EventLog.discard` before every state-transition assertion remains mandatory — connecting already buffers an empty `sentRequestsList`, so an "empty after action" wait passes vacuously without it.

Preview fixture: `test/preview/glass_preview.dart:159` — `'add' => AddOrInvitationsScreen()` becomes `'invitations' => InvitationsScreen()`, with `FriendsProvider` seeded through its socket handlers (raw JSON, same as the unit tests) to show all four row states at once: 2 inbound, 2 sent-pending, 1 accepted-ready, 1 accepted-not-ready.

### Phase 6 — Verification (serial)

```bash
cd backend && npx jest chat-friend-request     # focused, while iterating
cd frontend && flutter test test/providers     # focused, while iterating
cd backend && npm test
cd backend && npm run build
cd frontend && flutter analyze --no-fatal-infos
cd frontend && flutter test
docker-compose up                              # repo root, separate terminal
cd frontend && flutter test test_e2e
node scripts/impact.mjs                        # hint only, not coverage
```

Never pass a long explicit file list to `flutter test` — measured ≥5× slower than the full suite.

Then update the counts in root `CLAUDE.md` §3 (currently `541 unit tests, 47 suites` / `903 Flutter tests, 4 skipped`) and re-run both verifiers:

```bash
node scripts/verify-claude-backend-test-counts.mjs --log backend/test-output.txt
node scripts/verify-claude-frontend-test-counts.mjs
```

Counts are volatile — take them from this session's runs, never from this document.

### Phase 7 — Visual verification (required)

1. `cd frontend && flutter run -d web-server -t test/preview/glass_preview.dart` as a **background** job. Never block on it; it never exits.
2. Readiness = the compile/"serving" log **and** a non-blank screenshot (first compile 40–90 s), bounded ~120 s.
3. **Ask the owner before opening the browser tool** — it pops a visible window on this workstation.
4. Capture `?screen=invitations&theme={blue,dark,light,teal}` at phone and desktop widths — 8 shots.
5. Compare against `docs/design/liquid-glass/after/*.png` and `SPEC.md`; iterate on spacing, hierarchy, contrast, alignment, hover/focus, empty and loading states.
6. Design-review checkpoint (playbook §5): spawn the `designer` agent **read-only**, hand it the already-captured screenshots plus `SPEC.md` and the playbook, and tell it to read root `CLAUDE.md`, `frontend/CLAUDE.md` and `LATEST.md` (subagents inherit nothing). It MUST NOT launch `flutter run` or a render server — that hangs it.
7. Stop the render job in cleanup.

### Phase 8 — Cleanup

Write `.cursor/session-summaries/2026-07-28-invitation-implementation.md` (required sections: `# title`, `**Date:**`, `## What was done`, `## Key files`, `## Verification`, `## Notes for next session`), put a new entry on top of `LATEST.md` and shift the rest (≤5 entries, ≤2600 words total, ≤700 per entry — enforced by `.githooks/pre-commit`). Commit and `git push` on `feat/invitation-rework`.

**No `pubspec.yaml` bump** — the version bumps on a production release, and this branch is not being deployed. **No merge to `master`, no deploy, without explicit owner approval.**

---

## 3. Explicit non-goals

Withdraw/cancel invitation (no sender-authorized backend operation exists). A `Block` action on the invitation row — the research doc recommends one beside Accept/Decline, but the approved UX specifies Accept + quiet Decline only and Block already exists elsewhere; deferred deliberately, not overlooked. Pre-friend messages. Faux chat previews. New dependencies. Migrations. Redesigning Contacts, Chats, navigation, or the global theme. A domain-wide `FriendRequest` → `Invitation` rename (internal names may stay; a cosmetic cross-tier rename buys nothing).

**Durable accepted feedback for an OFFLINE sender** (Phase 4 scope boundary). Pre-existing behaviour, unchanged by this rework, stated rather than quietly inherited: acceptance is only delivered to a socket that is online at that moment, and nothing on reconnect replays it. Fixing it needs a schema change, so it is a separately-approved follow-up.

## 4. Risk register

| Risk | Mitigation |
|---|---|
| Stale PWA clients during a backend-ahead window | flat additive payload (§1.1); failure toast loss is stated and accepted (§1.3) |
| Contacts' build-level `consumePendingOpen` pushes chat under the open Invitations screen | acceptance no longer emits `openConversation`; the §1.7 retry is a correlated `ensureInvitationChat`/`invitationChatReady` pair that never emits `openConversation` at all |
| A client-side "swallow the next `openConversation`" flag eating an unrelated explicit navigation | rejected by design — §1.7 addresses the row by `peerUserId` and the attempt by a client token; `ConversationsProvider` is untouched |
| **Reciprocal auto-accept returns a request id neither client has** (`friends.service.ts:91-119` creates a new row and returns it) | §1.5.1: every identity — outcome key, list removal, row key, `_requestActions` cleanup, retry addressing — is the **peer user id**. Asserted by a provider round trip and a widget test that both deliver an accepted payload whose id differs from the seeded row |
| A stale retry attempt overwriting a fresh success | the outcome stores the current `correlationId`; results echoing a superseded token are dropped (§1.7), asserted by a provider test |
| An unbounded server-echoed token | `EnsureInvitationChatDto` bounds `correlationId` to `/^[A-Za-z0-9_-]{1,64}$/`; malformed input fails validation before any emit, asserted by Phase 1 test 12b |
| Accepted row flickering out, or duplicating, when the refreshed request lists land | §1.2 emits the accepted result before `friendRequestsList`/`sentRequestsList`, and `onFriendRequestAccepted` clears both pending lists **by peer** in one atomic swap. The guarantee is continuous presence — exactly one row per peer per frame — not element identity, since a reciprocal row legitimately moves between sections |
| Declined row vanishing before the server confirms | `onFriendRequestRejected` is the only retirement path; the row stays mounted and disabled until then |
| First-load skeleton ending early and flashing a false empty section | two snapshot flags, skeleton ends only when both incoming and sent have arrived; ordering test drives `friendRequestsList` alone and asserts the skeleton is still up |
| New status-pill colors failing contrast in one theme | WCAG 4.5:1 computed for all four themes before Phase 3 closes (playbook §1, SPEC §8) |
| An undismissed accepted row destroyed by a transient reconnect | `friendRequestAccepted` is never replayed, so `onConnect(true)` preserves `_acceptedOutcomes` and clears only action/retry state; `onConnect(false)` clears everything. Both directions asserted |
| Vacuous E2E assertions | `EventLog.discard` immediately before each transition; new `EventLog.none` for the negative case |
| Reintroducing the stale-snapshot race | no `getConversations()`/`getFriends()` in `onFriendRequestAccepted`; asserted by a test |
| Test-count verifiers going red | Phase 6 updates root `CLAUDE.md` §3 from this session's actual runs |

## 5. Definition of done

Every item from the handoff's "DONE MEANS", plus: `openConversation` has exactly one producer (`handleStartConversation`), `friendRequestFailed` carries enough identity to clear the correct row, no invitation identity anywhere is keyed on a request id that the reciprocal path can invalidate (§1.5.1), and the eight rendered screenshots have been inspected — not merely captured.
