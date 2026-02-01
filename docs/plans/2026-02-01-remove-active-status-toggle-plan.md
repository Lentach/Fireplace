# Remove Active Status Toggle - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the Active Status toggle entirely. Green dot = online (connected), gray dot = offline. No user preference.

**Architecture:** Full removal of activeStatus: drop from database, backend API, WebSocket, and frontend. Simplify isOnline to `onlineUsers.has(userId)` only.

**Tech Stack:** NestJS, TypeORM, Socket.IO, Flutter, Provider

---

## Task 1: Backend - Remove activeStatus from User entity

**Files:**
- Modify: `backend/src/users/user.entity.ts`

**Step 1:** Remove the activeStatus column (lines 28-29)

```typescript
// DELETE these lines:
@Column({ default: true })
activeStatus: boolean;
```

**Step 2:** Verify backend builds

Run: `cd backend && npm run build`
Expected: Success (TypeORM synchronize will drop column on next start)

---

## Task 2: Backend - Remove UpdateActiveStatusDto and PATCH endpoint

**Files:**
- Modify: `backend/src/users/dto/user.dto.ts` - Remove UpdateActiveStatusDto class
- Modify: `backend/src/users/users.controller.ts` - Remove import and PATCH handler
- Modify: `backend/src/users/users.service.ts` - Remove updateActiveStatus method

**Step 1:** In `user.dto.ts`, delete the UpdateActiveStatusDto class (lines 21-24)

**Step 2:** In `users.controller.ts`, remove UpdateActiveStatusDto from imports and delete the entire @Patch('active-status') method (lines 114-131)

**Step 3:** In `users.service.ts`, remove the updateActiveStatus method (lines 131-143)

**Step 4:** Run: `cd backend && npm run build`
Expected: Success

---

## Task 3: Backend - Simplify isOnline logic and remove updateActiveStatus handler

**Files:**
- Modify: `backend/src/chat/dto/chat.dto.ts` - Remove UpdateActiveStatusDto
- Modify: `backend/src/chat/services/chat-friend-request.service.ts`
- Modify: `backend/src/chat/chat.gateway.ts`

**Step 1:** In `chat.dto.ts`, delete UpdateActiveStatusDto class (lines 76-79)

**Step 2:** In `chat-friend-request.service.ts`:
- Remove UpdateActiveStatusDto from imports
- In toUserPayloadWithOnline: change `isOnline: onlineUsers.has(user.id) && user.activeStatus` to `isOnline: onlineUsers.has(user.id)`
- In toConversationPayloadWithOnline: change both userOne/userTwo isOnline to use only `onlineUsers.has(conv.userOne.id)` and `onlineUsers.has(conv.userTwo.id)`
- Change method signatures: `user: { id: number }` (remove activeStatus from type)
- Delete entire handleUpdateActiveStatus method (lines 652-712)

**Step 3:** In `chat.gateway.ts`, remove @SubscribeMessage('updateActiveStatus') and handleUpdateActiveStatus (lines 209-220)

**Step 4:** Run: `cd backend && npm run build`
Expected: Success

---

## Task 4: Backend - Simplify chat-conversation.service isOnline logic

**Files:**
- Modify: `backend/src/chat/services/chat-conversation.service.ts`

**Step 1:** In toConversationPayloadWithOnline, change:
- `isOnline: onlineUsers.has(conv.userOne.id) && conv.userOne.activeStatus` → `isOnline: onlineUsers.has(conv.userOne.id)`
- `isOnline: onlineUsers.has(conv.userTwo.id) && conv.userTwo.activeStatus` → `isOnline: onlineUsers.has(conv.userTwo.id)`
- Update type: remove activeStatus from userOne/userTwo in the conv parameter type

**Step 2:** In handleDeleteConversation friendsList mappings (lines 184-197), change:
- `isOnline: onlineUsers.has(u.id) && u.activeStatus` → `isOnline: onlineUsers.has(u.id)`

**Step 3:** Run: `cd backend && npm run build`
Expected: Success

---

## Task 5: Backend - Remove activeStatus from auth and UserMapper

**Files:**
- Modify: `backend/src/auth/auth.service.ts` - Remove activeStatus from login payload
- Modify: `backend/src/auth/strategies/jwt.strategy.ts` - Remove activeStatus from validate return
- Modify: `backend/src/chat/mappers/user.mapper.ts` - Remove activeStatus from toPayload

**Step 1:** In auth.service.ts, remove `activeStatus: user.activeStatus` from payload (line 60)

**Step 2:** In jwt.strategy.ts, remove activeStatus from payload type and return object (lines 24, 35)

**Step 3:** In user.mapper.ts, remove `activeStatus: user.activeStatus` from toPayload (line 10)

**Step 4:** Run: `cd backend && npm run build`
Expected: Success

---

## Task 6: Frontend - Remove toggle and active status from Settings screen

**Files:**
- Modify: `frontend/lib/screens/settings_screen.dart`

**Step 1:** Remove state variables: `_activeStatus`, `_activeStatusSyncedFromAuth`

**Step 2:** Remove `didChangeDependencies` override (or simplify to not sync activeStatus)

**Step 3:** Remove `_updateActiveStatus` method

**Step 4:** Change AvatarCircle isOnline from `_activeStatus && chat.socket.isConnected` to `chat.socket.isConnected`

**Step 5:** Remove the Active Status tile (_buildSettingsTile for 'Active Status' with Switch)

**Step 6:** Run: `cd frontend && flutter analyze`
Expected: May have errors until we fix SocketService and ChatProvider (missing onUserStatusChanged)

---

## Task 7: Frontend - Remove updateActiveStatus and onUserStatusChanged from SocketService

**Files:**
- Modify: `frontend/lib/services/socket_service.dart`

**Step 1:** Remove `onUserStatusChanged` from connect() parameters

**Step 2:** Remove `_socket!.on('userStatusChanged', onUserStatusChanged);` line

**Step 3:** Remove `updateActiveStatus` method (lines 134-138)

---

## Task 8: Frontend - Remove onUserStatusChanged from ChatProvider

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`

**Step 1:** Remove the entire onUserStatusChanged callback from the connect() call (or pass a no-op if SocketService still requires it - but we're removing the param, so we need to update the call site)

**Step 2:** In ChatProvider.connect(), remove the onUserStatusChanged: (data) { ... } callback. The SocketService will no longer have this param, so we need to not pass it.

---

## Task 9: Frontend - Remove updateActiveStatus from ApiService and AuthProvider

**Files:**
- Modify: `frontend/lib/services/api_service.dart` - Remove updateActiveStatus method
- Modify: `frontend/lib/providers/auth_provider.dart` - Remove activeStatus from user parsing (if used)
- Modify: `frontend/lib/models/user_model.dart` - Remove activeStatus field

**Step 1:** In api_service.dart, remove the updateActiveStatus method

**Step 2:** In auth_provider.dart, remove activeStatus from the user object when parsing JWT (login and fromToken)

**Step 3:** In user_model.dart, remove activeStatus from the class, constructor, fromJson, and copyWith

---

## Task 10: Frontend - Simplify isOnline check in ConversationTile and ChatDetailScreen

**Files:**
- Modify: `frontend/lib/widgets/conversation_tile.dart`
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

**Step 1:** In conversation_tile.dart, change:
`isOnline: otherUser != null && (otherUser!.activeStatus == true) && (otherUser!.isOnline == true)`
to:
`isOnline: otherUser?.isOnline == true`

**Step 2:** In chat_detail_screen.dart, change:
`showOnline = otherUser != null && (otherUser.activeStatus == true) && (otherUser.isOnline == true)`
to:
`showOnline = otherUser?.isOnline == true`

---

## Task 11: Update CLAUDE.md and session summary

**Files:**
- Modify: `CLAUDE.md`
- Create: `.cursor/session-summaries/2026-02-01-remove-active-status.md`
- Modify: `.cursor/session-summaries/LATEST.md`

**Step 1:** Update CLAUDE.md - Replace active status section with: "Online indicator (green dot) shows when user is connected via WebSocket. No toggle. isOnline = onlineUsers.has(userId)."

**Step 2:** Create session summary for this change

**Step 3:** Update LATEST.md to point to new summary

---

## Verification

1. Backend: `cd backend && npm run build`
2. Frontend: `cd frontend && flutter analyze`
3. Manual: Login, see green dot on own avatar in Settings when connected. Friends list: green dot for online friends only.
