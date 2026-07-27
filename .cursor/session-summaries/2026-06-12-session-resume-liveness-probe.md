# Resume liveness probe + lifecycle instrumentation (push-arrives-but-message-missing)

**Date:** 2026-06-12

## What was done
User-reported on device: push notification arrives but the new message does not appear in the app — only after a full relaunch. Root cause identified from source: `ConnectionProvider.ensureReconnectIfNeeded` returned immediately when `_socketService.isConnected` was true — but on iOS PWA resume, socket.io's `connected` flag lies (iOS suspended the transport; the client only learns at ping timeout), so resume did NOTHING: no reconnect, no re-fetch — the message sat server-side until relaunch built a fresh socket. **Fix (self-healing + self-documenting):** claims-connected resume now (1) re-syncs immediately (`getConversations` + `getMessages(active)`), (2) arms a 6s liveness probe — if no `conversationsList`/`messageHistory` response bumps `_serverResponseCounter`, forces `connect()` (lossless reconnect, cooldown-guarded). **Instrumentation (ids/booleans only)** across the whole resume chain: `RESUME_CHECK{socketConnected}` / `RESUME_RESYNC{activeConvId}` / `RESUME_PROBE_TIMEOUT`, `SOCKET_CONNECT/DISCONNECT{intentional}/READY{activeConvId}` (ConnectionProvider), `LIFECYCLE{state,loggedIn}` + `TAB_VIS{visible}` (MainShell), `CONV_LIST{count,ignoredEmpty}` (ConversationsProvider), `HISTORY_REQ{convId,seq,emitWired}` + `HISTORY_RESP{convId,count,activeId,paginationId}` + `HISTORY_DROP{reason: badPayload|convMismatch|notActiveNotPagination|staleSeq}` (every silent exit in `onMessageHistory` now names itself). Test seam: `ConnectionProvider.setIdentityForTest`.

Also this session (earlier): analyzed user's first diag capture — msg 8592 NoSession/ctype-2 was the designed Class A one-message loss + clean recovery (cascade fix visibly working); huge-bubble context-menu fix shipped as 0.0.52/`6a74ac1`.

## Key files
- `frontend/lib/providers/connection_provider.dart` (probe + counter + socket events + test seam)
- `frontend/lib/providers/messaging/messaging_provider.history.dart` (HISTORY_REQ/RESP/DROP)
- `frontend/lib/providers/conversations_provider.dart` (CONV_LIST), `frontend/lib/screens/main_shell.dart` (LIFECYCLE/TAB_VIS)
- Tests: `frontend/test/providers/connection_provider_resume_probe_test.dart` (new, 3: dead-socket immediate reconnect; zombie → resync + probe-timeout forced reconnect; probe disarmed by server response)

## Verification
- 3 new probe tests green (fakeAsync timer control; fake `SocketService` via injectable ctor param).
- Full suite **371 passed**, `flutter analyze` **zero issues**. Version 0.0.54.

## Notes for next session
- **Deploy 0.0.54** then reproduce: background the app on iPhone, have peer send (push arrives), reopen via app icon (NOT the notification). Expected now: message appears within ~6s worst-case (probe forces reconnect). 
- **Capture protocol if it still fails:** do NOT relaunch — the diag log is in-memory and dies with the app. Go straight to Privacy & Safety → long-press shield → Copy. The interesting sequence: `TAB_VIS{visible:true}`/`LIFECYCLE{resumed}` → `RESUME_CHECK{socketConnected:?}` → then either `RESUME_RESYNC`→`HISTORY_RESP` (good), `RESUME_PROBE_TIMEOUT` (zombie confirmed, self-healed), or a `HISTORY_DROP{reason}` (a guard ate the refresh — that reason is the bug).
- Open hypothesis if RESUME_CHECK never appears in the capture: iOS didn't deliver visibility/lifecycle events at all → different lever (pageshow/focus listeners).
