# Session: Live-receive drop fixed — iOS PWA resume re-assert (0.0.58)

**Date:** 2026-06-16

## What was done
Confirmed and fixed the intermittent iOS-PWA bug: **received messages don't appear
live in the open chat** (a web push fires; reopening the chat shows them; the screen
is not frozen — typing/sending work).

**Confirmation (from the temp `E2eDiagLog` diagnostic the user captured on-device):**
After an iOS background→resume + socket reconnect, while conversation 77 was on screen:
```
RECV_MSG    {msgConvId: 77, activeId: null, paginationConvId: -1, ...}
ADD_TO_STATE{msgConvId: 77, activeId: null, paginationConvId: -1, appendedToOpenChat: false}
HISTORY_RESP{convId: 77, activeId: -1, paginationId: -1}   ← state restored ~2s too late
```

**Root cause:** `ChatDetailScreen.dispose()` fires during iOS resume churn →
`_clearActiveConversationIfThisChat()` → `closeConversation()` + `clearMessages()`
null `activeConversationId` / `_paginationConversationId`. `_addMessageToState`'s gate
(`msg.conversationId == (activeConversationId ?? _paginationConversationId)`) then drops
incoming messages from the open chat, while `updateLastMessage` still runs unconditionally
(so the conversation list updates but the chat doesn't). Auto-recovery otherwise depends
on a race: `_onSocketReady` re-fetches the open chat only if `activeConversationId != null`
at that instant; if the dispose-null wins, nothing re-fetches → missing until manual reopen.

**Fix (TDD, RED→GREEN):**
- New `frontend/lib/utils/chat_resume_reassert.dart` — `reassertOpenConversationOnResume(convs, messaging, convId)` = `openConversation` + `loadCachedMessages` + `getMessages`.
- `ChatDetailScreen.didChangeAppLifecycleState(resumed)` calls it (screen is already a `WidgetsBindingObserver`). Re-sets the active id (+ re-emits `pushClientState`) and refetches the open chat deterministically on every resume.
- Test `frontend/test/utils/chat_resume_reassert_test.dart`: a unit test on the real
  function + a real-lifecycle host test (fires `handleAppLifecycleStateChanged(resumed)`).
  The real `ChatDetailScreen` can't be full-mounted (its `build` needs `AuthProvider.currentUser`,
  no test seam) — same constraint the `main_shell_notification_nav_test` host pattern works around.

## Key files
- `frontend/lib/utils/chat_resume_reassert.dart` (new) — the fix logic
- `frontend/lib/screens/chat_detail_screen.dart` — `didChangeAppLifecycleState` hook + import
- `frontend/test/utils/chat_resume_reassert_test.dart` (new) — regression
- `CLAUDE.md` — "Live-receive resume re-assert (iOS PWA)" bullet
- `frontend/pubspec.yaml` — 0.0.58

## Verification
- `flutter analyze` (changed files) → No issues found
- `flutter test test/` → All tests passed (**377**)
- RED first confirmed (function missing → compile fail), then GREEN.

## Notes for next session
- **Diagnostic still in place** (`RECV_MSG` enriched, `RECV_QUEUED`, `ADD_TO_STATE` in
  `messaging_provider.events.dart` / `.history.dart`). Once the user confirms the fix
  on their iPhone (live messages appear without reopening), **remove those entries** and
  bump a patch.
- Repo-state note: this machine's `master` is on the security-fixes line (PR #10, was
  v0.0.57). The earlier 2026-06-09 work (bubble text-align, the diagnostic itself) is
  present in the code on this line; session-summary dates from that stale snapshot
  don't reflect this history.
