# Session: Live-receive drop diagnostic (iOS PWA) + v0.0.46

**Date:** 2026-06-09

## What was done
Investigating an intermittent, iOS-PWA-only bug reported by the user:
**received messages don't appear live in the open chat** — a web push notification
arrives, but the new bubble doesn't show until the user leaves/reopens the chat
screen. The screen is NOT frozen (typing and sending work); only *incoming* live
messages are missing. Uncommon / not every time.

Brainstormed and traced the code (no fix yet — diagnostic-first by user choice):

- Web push and the live socket are **independent** channels. The server only pushes
  when it believes the client is away (`pushClientState`), so push-while-in-chat
  means the server thinks this client isn't watching the conversation.
- `_addMessageToState` appends to the open chat **only when**
  `msg.conversationId == (activeConversationId ?? _paginationConversationId)`, while
  `updateLastMessage` (conversation-list reorder) runs **unconditionally** right
  after — which matches the "list updates but open chat doesn't" symptom.
- `ChatDetailScreen` sets the active id once in `initState` and has **no**
  `didChangeAppLifecycleState` resume handler, so nothing re-asserts it after an
  iOS suspend/resume while the widget stays mounted.

**Leading hypothesis:** active-conversation desync — both
`ConversationsProvider._activeConversationId` and `MessagingProvider._paginationConversationId`
go stale while the chat stays open; the same stale active id makes `pushClientState`
report "away", explaining the push. (Secondary: a stuck `_decryptingHistory` queue —
explains the missing message but not the push.)

**Diagnostic added (observability only, no behavior change):** three `E2eDiagLog`
entries on the incoming path —
- `RECV_MSG` enriched with `msgConvId / activeId / paginationConvId / decryptingHistory`
- `RECV_QUEUED` (new) when a message is shunted into the history-decrypt queue
- `ADD_TO_STATE` (new) recording `appendedToOpenChat` + both id fields at the decision point

Bumped version `0.0.45 → 0.0.46` to ship the diagnostic to prod (user deploys from
the production machine).

## Key files
- `frontend/lib/providers/messaging/messaging_provider.events.dart` — RECV_MSG / RECV_QUEUED logs
- `frontend/lib/providers/messaging/messaging_provider.history.dart` — ADD_TO_STATE log in `_addMessageToState`
- `frontend/pubspec.yaml` — version 0.0.46

## Verification
- `flutter analyze` (both edited files) → No issues found
- `flutter test test/providers/messaging_provider_race_test.dart` → All tests passed (22)
- Commits: `8203dff` (diagnostic), version-bump commit (this session). Also pushing
  the earlier unpushed `6e47353` (CLAUDE.md condense) and `cb342c3` was already pushed.

## How to capture the log (user, on iPhone)
1. When a received message doesn't appear live, **do not reopen the chat / reload the PWA**.
2. Navigate in-app to Settings → Privacy & Safety.
3. Long-press the shield icon → Copy → paste the log back.
4. Look for `ADD_TO_STATE` with `appendedToOpenChat: false`; the adjacent
   `activeId` / `paginationConvId` reveal which field went stale. `RECV_QUEUED`
   instead would point at the decrypt-queue theory.

## Notes for next session
- **Remove the three diagnostic log entries** once root cause is confirmed.
- Likely fix once confirmed: add `didChangeAppLifecycleState` to `ChatDetailScreen`
  that re-asserts `openConversation(widget.conversationId)` on `resumed` (re-sets
  active id, re-emits `pushClientState`, refetches). Targeted at the iOS resume window.
- E2eDiagLog is in-memory (200-entry ring, resets on restart) — capture before any reload.
