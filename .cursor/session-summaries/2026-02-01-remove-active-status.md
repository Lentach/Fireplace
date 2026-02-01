# Session: Remove Active Status Toggle

**Date:** 2026-02-01

## Goal

Completely remove the "Active Status" toggle that allowed users to appear offline. Simplify online indicator: green dot = connected, gray dot = offline. No user preference.

## Changes

### Backend
- **User entity:** Removed `activeStatus` column (TypeORM synchronize will drop on next start)
- **DTOs:** Removed `UpdateActiveStatusDto` from user.dto.ts and chat.dto.ts
- **UsersController:** Removed PATCH `/users/active-status` endpoint
- **UsersService:** Removed `updateActiveStatus()` method
- **ChatFriendRequestService:** Removed `handleUpdateActiveStatus()`, simplified `toUserPayloadWithOnline` and `toConversationPayloadWithOnline` — `isOnline` now only checks `onlineUsers.has(userId)`
- **ChatGateway:** Removed `@SubscribeMessage('updateActiveStatus')`
- **ChatConversationService:** Simplified `toConversationPayloadWithOnline` and friendsList emissions — `isOnline: onlineUsers.has(u.id)` only
- **Auth:** Removed `activeStatus` from JWT payload (auth.service.ts, jwt.strategy.ts)
- **UserMapper:** Removed `activeStatus` from toPayload

### Frontend
- **SettingsScreen:** Removed Active Status tile, `_activeStatus`, `_activeStatusSyncedFromAuth`, `_updateActiveStatus()`, `didChangeDependencies` sync. Own avatar now uses `isOnline: chat.socket.isConnected` only. Removed unused device_info_plus import.
- **SocketService:** Removed `onUserStatusChanged` param, `userStatusChanged` listener, `updateActiveStatus()` method
- **ChatProvider:** Removed `onUserStatusChanged` callback
- **ApiService:** Removed `updateActiveStatus()` method
- **UserModel:** Removed `activeStatus` field
- **AuthProvider:** Removed `activeStatus` from UserModel when parsing JWT
- **ConversationTile, ChatDetailScreen:** `isOnline: otherUser?.isOnline == true` (backend sends correct value)

### Documentation
- **CLAUDE.md:** Updated Online indicator section, database schema, WebSocket events, REST endpoints, User Settings feature
- **docs/plans/2026-02-01-remove-active-status-toggle-design.md:** Design document
- **docs/plans/2026-02-01-remove-active-status-toggle-plan.md:** Implementation plan

## Follow-up: Remove online indicator (green dot)

- Removed `showOnlineIndicator` and `isOnline` from AvatarCircle
- Removed the green/gray dot from all avatars (Settings, ConversationTile, ChatDetailScreen)

## Follow-up: Remove isOnline entirely

- **Backend:** Removed `toUserPayloadWithOnline` and `toConversationPayloadWithOnline`; all payloads use `UserMapper.toPayload` and `ConversationMapper.toPayload` (no isOnline). `handleGetFriends` and `handleGetConversations` no longer receive `onlineUsers`.
- **Frontend:** Removed `isOnline` from UserModel. Removed `isConnected` getter from SocketService.

## Verification

- Backend: `npm run build` — success
- Frontend: `flutter analyze` — 2 info-level issues (prefer_final_fields, unrelated)

## Files Modified

**Backend:** user.entity.ts, user.dto.ts, users.controller.ts, users.service.ts, chat.dto.ts, chat-friend-request.service.ts, chat-conversation.service.ts, chat.gateway.ts, auth.service.ts, jwt.strategy.ts, user.mapper.ts

**Frontend:** settings_screen.dart, socket_service.dart, chat_provider.dart, api_service.dart, user_model.dart, auth_provider.dart, conversation_tile.dart, chat_detail_screen.dart

**Docs:** CLAUDE.md, new design and plan docs
