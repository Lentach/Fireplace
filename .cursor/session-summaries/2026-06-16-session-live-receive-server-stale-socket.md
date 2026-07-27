# Session: Live-receive Bug B — server-side stale-socket eviction (backend fix)

**Date:** 2026-06-16

## What was done
Found and fixed a SECOND, independent cause of "received messages don't appear live
in the open chat; a web push notification arrives instead" — separate from Bug A
(the iOS-resume active-conversation desync fixed earlier the same day).

**Evidence (on-device diag log, captured AFTER the Bug A fix shipped):**
- Bug A confirmed fixed: msgId 9898 (peer 48, right after resume) → `RECV_MSG` +
  `ADD_TO_STATE appendedToOpenChat:true` + `DECRYPT_OK`. Appears live. ✓
- Bug B: msgId 9900 (peer 48, ~20s after resume) had **no `RECV_MSG` and no
  `RECV_QUEUED`** — `_handleIncomingMessage` was never called → the server's live
  `newMessage` never reached the client. It only surfaced at 06:18:29 via a later
  `getMessages` history refetch. Own sends (9899/9901) echoed fine throughout.

**Root cause (server):** `ChatGateway` tracks `onlineUsers: Map<userId, socketId>`
(one socket per user); `newMessage` delivery is
`server.to(onlineUsers.get(recipientId)).emit(...)`, else push fallback
(`chat-message.service.ts`). `handleDisconnect` deleted the entry **unconditionally**
(`onlineUsers.delete(userId)`). iOS suspend/resume: device reconnects with a NEW
socket (`handleConnection` sets `onlineUsers[uid] = newId`); ~20s later the abandoned
OLD socket times out server-side and its `handleDisconnect` runs → deletes
`onlineUsers[uid]` even though it now points at the live NEW socket. From then on
`onlineUsers.get(recipientId)` is `undefined` → peers' messages fall back to push.
Own sends keep working because they echo via `client.emit('messageSent')` on the live
socket, not via the map — so only *peer* messages disappear.

This matches the ~20s delay (Socket.IO ping-timeout for the abandoned socket), the
notification-but-no-message symptom, and "my sends arrive but theirs don't".

**Fix (TDD):** guarded delete — only `onlineUsers.delete(userId)` when
`onlineUsers.get(userId) === client.id`. A stale old-socket teardown can no longer
evict the live socket.

## Key files
- `backend/src/chat/chat.gateway.ts` — `handleDisconnect` guarded delete
- `backend/src/chat/chat.gateway.spec.ts` — new "stale-socket guard" describe (2 tests)
- `CLAUDE.md` — backend "Online-socket map (guarded disconnect)" gotcha; test count 305→307

## Verification
- RED first: new test failed `Expected "NEW", Received undefined` (live socket evicted).
- GREEN after the guard. Gateway spec: 6/6.
- Full backend suite: **40 suites, 307 tests passed** (was 305).

## Deploy / verify
- Backend-only — **no frontend version bump** (pubspec stays 0.0.58; the frontend
  bundle is unchanged). Deploy on the VM: `git pull && docker compose build backend
  && docker compose up -d backend`. Verify `/version` `gitCommit` matches HEAD.
- On-device check: after backgrounding/resuming, have the peer send a message ~30s
  later — it should now arrive live (no push-only). The diag log should show a
  `RECV_MSG` for it (no longer only-via-history).

## Notes for next session
- The two live-receive bugs (A: client active-id desync; B: server stale-socket
  eviction) share the iOS suspend/resume connection-overlap root but live in different
  layers. Both now fixed.
- The temp `E2eDiagLog` entries (`RECV_MSG`/`RECV_QUEUED`/`ADD_TO_STATE`) are still in
  the frontend — remove once both fixes are confirmed on-device over real use.
- Pre-existing doc drift noticed: CLAUDE.md references
  `scripts/verify-claude-backend-test-counts.mjs`, which doesn't exist in this repo
  line. Left as-is (out of scope); count updated to 307 manually.
