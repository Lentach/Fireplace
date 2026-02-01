# Active Status Toggle Removal - Design Document

**Date:** 2026-02-01

## Problem

The "Active Status" toggle in Settings works incorrectly. It was meant to let users appear offline (hide green dot) while still being connected. The user wants it **completely removed**.

## Target Behavior (Simplified)

- **Green dot** = user is online (logged in + WebSocket connected)
- **Gray dot** = user is offline (disconnected)
- **No toggle** — visibility is purely based on connection state

## Current vs Target

| Aspect | Current | Target |
|--------|---------|--------|
| isOnline logic | `onlineUsers.has(userId) && user.activeStatus` | `onlineUsers.has(userId)` only |
| Settings | Toggle to show/hide | No toggle |
| Own avatar (Settings) | `_activeStatus && isConnected` | `isConnected` only |
| Backend | PATCH /users/active-status, updateActiveStatus WebSocket, userStatusChanged event | Remove all |
| Database | users.activeStatus column | Remove column |

## Components to Remove

### Backend
- `UpdateActiveStatusDto` (user.dto.ts)
- PATCH `/users/active-status` endpoint (users.controller.ts)
- `updateActiveStatus()` in UsersService
- `handleUpdateActiveStatus` in ChatFriendRequestService
- `@SubscribeMessage('updateActiveStatus')` in ChatGateway
- `activeStatus` column from User entity

### Frontend
- Active Status tile (Switch) from Settings screen
- `_activeStatus`, `_activeStatusSyncedFromAuth`, `_updateActiveStatus()` from SettingsScreen
- `updateActiveStatus()` in SocketService
- `updateActiveStatus()` in ApiService
- `onUserStatusChanged` listener and handler in ChatProvider/SocketService
- `activeStatus` from UserModel (optional: keep for backward compatibility with old JWT, treat as ignored)

### Logic Changes
- Backend: all `isOnline` = `onlineUsers.has(userId)` (remove `&& user.activeStatus`)
- Frontend: Settings avatar `isOnline: chat.socket.isConnected` (remove `_activeStatus &&`)
- Frontend: ConversationTile, ChatDetailScreen — use `otherUser.isOnline` directly (backend sends correct value)
- Auth: remove `activeStatus` from JWT payload and AuthProvider (or leave in JWT for backward compat, ignore on frontend)

## Data Flow After Change

1. User connects → added to onlineUsers
2. Friends call getFriends/getConversations → backend returns isOnline: true for connected users
3. User disconnects → removed from onlineUsers
4. Next time friends fetch lists → isOnline: false
5. No real-time push for connect/disconnect (same as before — userStatusChanged was only for toggle)

## Edge Cases

- **Old clients:** If we remove activeStatus from backend responses, old app versions might crash. Safer: keep activeStatus in User entity as `true` default, but remove the toggle and stop using it in isOnline logic. We can do a clean removal since this is MVP and we control both ends.
- **Migration:** Removing column with TypeORM synchronize:true will drop it on next backend start. Existing DB: column gets dropped. No data loss concern.

## Recommendation

Full removal: drop activeStatus from entity, DTOs, JWT, frontend model. Simpler codebase.
