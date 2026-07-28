# Invitation rework — implementation plan locked

**Date:** 2026-07-28 — planning session in worktree `fireplace-wt-invitation`, branch `feat/invitation-rework`. No application source, test, config, migration or version file changed.

## What was done

Turned the approved invitation-rework design into an executable plan and resolved every decision the handoff deferred to source inspection. Two read-only scouts traced both tiers; every load-bearing anchor was re-verified by hand before it entered the plan.

Decisions locked:

1. **`friendRequestAccepted` becomes the authoritative accepted result, flat and additive** — request payload + `conversationId: int|null` + `chatReady: bool`, built at the emit site so `FriendRequestMapper` stays pure (five other events share it). Not nested: the backend deploys ahead of the web bundle, and a nested payload would throw inside `FriendRequestModel.fromJson` on every acceptance for every already-loaded PWA client.
2. **Emitted after `conversationsList`, before `friendRequestsList`/`sentRequestsList`.** After the conversation list so `Open chat` resolves locally and the documented ban on refetching inside `onFriendRequestAccepted` survives. Before the request lists because those no longer contain the request — landing first, they unmount the acting row and the transform becomes a flicker.
3. **New `friendRequestFailed {action, requestId, recipientId, reason}`** replaces the generic `error` in the three friend-request handlers. The backend has no socket-ack path and no exception filter anywhere, so a new event following the `editMessageFailed` precedent is the only honest option. Clean cutover; the stale-client toast gap is stated and accepted.
4. **`openConversation` loses both acceptance emitters** (`chat-friend-request.service.ts:162`, `:401`) and keeps exactly one producer, `handleStartConversation`.
5. **Invitation identity is the PEER USER ID, never the request id.** `friends.service.ts:91-119` — verified, not assumed — shows the reciprocal path does **not** reuse the reverse pending row: it creates a new row, accepts both, and returns the **new** one. So a reciprocal `friendRequestAccepted` carries an id that exists in neither client's lists, and every by-id cleanup misses on both sides at once (stale pending row + stuck `Accept` spinner + phantom accepted row). Latent before, because the old ordering had a full list refresh right behind it; decision 2 makes it visible. Outcome map, list removal, row key, `_requestActions` cleanup and retry addressing are all peer-keyed. Direction precedence is `_sendActions` → `_friendRequests` → `_sentRequests` → payload role, in that order, because the reciprocal second sender satisfies the first two at once and the locked UX puts their row under `Sent`.
6. **Partial-success retry is correlated, not suppressed.** `ensureInvitationChat {peerUserId, correlationId}` → `invitationChatReady {peerUserId, correlationId, conversationId, chatReady, reason?}`, authorized by `ChatValidationService.validateCanMessage`, idempotent via `findOrCreate`. Peer addresses the row; the client-minted token addresses the attempt, so a slow first failure cannot clobber a fast second success. The token is bounded at the DTO (`/^[A-Za-z0-9_-]{1,64}$/`) because the server echoes it. A client-side "swallow the next `openConversation`" flag was designed and rejected — uncorrelated, it would eat a concurrent explicit navigation. `ConversationsProvider` is untouched.
7. **Every server confirmation is an atomic swap in one notification.** `onFriendRequestSent` clears the send flag *and* inserts the sent row (the backend emits it separately from `sentRequestsList`); `onFriendRequestAccepted` clears the accept flags **by peer**, clears any `_sendActions` entry (reciprocal auto-accept never emits `friendRequestSent`, so the caller's spinner would otherwise hang), removes both pending rows for that peer, and inserts the outcome; `onFriendRequestRejected` is the only thing that retires a declined row. No optimistic UI, and no frame where a row is missing or doubled.
8. `InvitationOutcome` carries `direction` captured at record time. Row keys give in-place updates only *within* a section — a reciprocal row moves between sections and remounts — so the tested guarantee is continuous presence (exactly one row per peer per frame), not element identity.
9. `Open chat` pops the peer `userId`; `ContactsScreen._openChatWithContact` already branches desktop vs mobile.
10. Glass on the floating header only; status pills are solid theme-token fills, contrast-gated at 4.5:1 in all four themes. The row state change is `easeInOut` 200 ms (playbook §2 treats state changes separately from entrances). The first-load skeleton ends only when **both** list snapshots have arrived.

No migration, no dependency, no `FriendRequestModel` change, no parallel state module, no `pubspec.yaml` bump.

## Key files

- `docs/plans/2026-07-28-invitation-implementation-plan.md` — the canonical plan (8 phases, locked contracts, risk register, definition of done). **New.**
- `.planning/invitation-rework/{task_plan,findings,progress}.md` — local, gitignored: phase tracker plus the full line-referenced source trace of both tiers.
- Anchors that will change: `backend/src/chat/services/chat-friend-request.service.ts` (`:138-171`, `:282-403`), its spec (14 `it()`s, `:146` asserts the `openConversation` we are deleting), `backend/src/chat/chat.gateway.ts`, `frontend/lib/providers/friends_provider.dart`, `frontend/lib/screens/add_or_invitations_screen.dart` → `invitations_screen.dart`, `frontend/test_e2e/{full_stack_e2e_test,stale_otp_epoch_test}.dart`.

## Verification

No tests run — no code changed. Verified by reading/grep only: exactly three `openConversation` producers in the chat services, `findOrCreate` throwing rather than returning null, the absence of any socket ack or exception filter in `backend/src`, 14 `it()`s in the friend-request spec, the single consumer of `consumeFriendRequestSent`, the four `consumePendingOpen` consumers, and the `IgnorePointer` in `showTopSnackBar` that currently blocks an `Open chat` action.

## Notes for next session

- Phases 1–4 of the plan are genuinely parallel; their shared contracts are frozen in plan §1, so they can be dispatched in one batch. Phase 5 (E2E + preview) needs 1 and 2.
- `EventLog` has `next`/`discard` but **no negative assertion** — `EventLog.none(event, within:)` has to be added before the "no `openConversation` on accept" E2E check can exist. And `discard` immediately before every state transition, or the assertion passes vacuously on the connect-time empty buffer.
- SPEC §10 says "no title pills"; SPEC §11 (later, and matching current source) keeps a title pill on the add/invitations header. §11 wins for this surface — only the tab capsule goes.
- Test counts in root `CLAUDE.md` §3 (541/47 backend, 903+4 Flutter) are volatile — re-measure in the implementation session, then re-run both verifier scripts.
- Ask the owner before opening the browser tool for the four-theme render loop.
