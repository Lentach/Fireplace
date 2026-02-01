# CLAUDE.md - MVP Chat App Knowledge Base

**Last updated:** 2026-02-01

**MANDATORY RULE: Keep This File Up To Date**

---

## ✅ RECENT CHANGE - Light Mode Color Renovation (2026-02-01)

**Design:** Modern neutral palette (Slack-inspired). Purple accent #4A154B replaces gold in light mode. Soft grays (#F4F5F7 main, #FFFFFF surface), high-contrast text (#1D1C1D primary, #616061 secondary).

**Changes:**
- **RpgTheme:** New `primaryLight`, `primaryLightHover`, `textSecondaryLight`, `activeTileBgLight`, `mineMsgBgLight`, `theirsMsgBgLight`, etc. `themeDataLight` uses primaryLight (not gold) for ColorScheme.primary. Helpers: `isDark(context)`, `primaryColor(context)`, `surfaceColor(context)`.
- **Theme-aware widgets:** All screens and widgets use `Theme.of(context).colorScheme` or `RpgTheme.isDark(context)` for colors. ConversationTile, ConversationsScreen, ChatDetailScreen, ChatInputBar, ChatMessageBubble, AvatarCircle, MessageDateSeparator, SettingsScreen, dialogs, AuthScreen, AuthForm, FriendRequestsScreen, NewChatScreen.
- **Sidebar header:** Same color as rest (colorScheme.surface), logo uses colorScheme.primary.
- **rpgInputDecoration:** Optional `context` param for theme-aware icon color.

**Plan:** `docs/plans/2026-02-01-light-mode-color-renovation.md`

---

## ✅ RECENT CHANGE - Light/Dark Theme + Active Status Green Dot (2026-02-01)

**Theme:**
- Default theme preference is **dark** (was system). SettingsProvider default `_darkModePreference = 'dark'`, load fallback `'dark'`.
- **RpgTheme.themeDataLight** added: light palette (backgroundLight, boxBgLight, textColorLight, etc.) and `themeDataLight` getter (ThemeData.light() with same structure as dark).
- **main.dart:** `theme: RpgTheme.themeDataLight`, `darkTheme: RpgTheme.themeData` so ThemeMode.light/dark switch immediately.
- Settings screen: tile label "Dark Mode" → "Theme" with subtitle "System / Light / Dark"; Settings tiles use theme-aware colors (colorScheme.surface, onSurface).

**Active status + green dot:**
- **JWT:** AuthService.login() and JwtStrategy.validate() include `activeStatus` in payload/return so frontend gets it on login and from saved token.
- **Backend:** All `friendsList` and `conversationsList` emissions now include `isOnline: onlineUsers.has(user.id)` (or per userOne/userTwo in conversations). getFriends and getConversations accept `onlineUsers`; ChatFriendRequestService and ChatConversationService enrich payloads with isOnline.
- **Frontend:** UserModel has `isOnline` (bool?); AuthProvider sets `activeStatus` from JWT in login and _loadSavedToken. Settings screen init: _activeStatus synced from auth.currentUser?.activeStatus once in didChangeDependencies.
- **Green dot:** Shown only when `activeStatus == true` **and** `isOnline == true`. ConversationTile and ChatDetailScreen pass `otherUser` (UserModel) to AvatarCircle with showOnlineIndicator and isOnline; Settings avatar shows dot only when _activeStatus is on. ChatProvider.getOtherUser(conv) added; onUserStatusChanged updates both _friends and _conversations so green dot updates in real time when a friend toggles status.

**After EVERY code change (bug fix, new feature, refactor, config change), update this file immediately.** This is the single source of truth for future agents.A future agent must be able to read ONLY this file and understand the current state of the project without reading every source file

**Sessions:** At the start, the agent reads `.cursor/session-summaries/LATEST.md`; at the end, it writes a summary to `.cursor/session-summaries/YYYY-MM-DD-session.md` and updates `LATEST.md`. Rule: `.cursor/rules/session-summaries.mdc`

**Code language:** Always write code in English (variables, functions, comments, commits). Rule: `.cursor/rules/code-in-english.mdc`

---

## ✅ RECENT CHANGE - Cloudinary Avatar Storage (2026-02-01)

**Migrated:** Profile pictures from local disk to Cloudinary cloud storage.

**Changes:**
- Avatars are uploaded to Cloudinary (free tier: 25 GB storage, 25 GB bandwidth/month)
- Backend uses `cloudinary` npm package, Multer `memoryStorage`, `CloudinaryService`
- Database: `profilePictureUrl` stores full Cloudinary URL; `profilePicturePublicId` stores public_id for deletion
- Frontend `AvatarCircle`: handles both absolute URLs (Cloudinary) and relative paths (legacy)
- Removed: local `./uploads/` storage, nginx `/uploads/` proxy, Docker uploads volume

**Required setup:** Create `.env` in project root (or set in docker-compose) with:
- `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`
- Get from [cloudinary.com](https://cloudinary.com) Dashboard → API Keys

---

## ✅ PREVIOUSLY CRITICAL ISSUE - NOW RESOLVED

**BUG (FIXED):** New users saw conversations/friends from previously logged-out users.

**Root cause:** Two issues combined:
1. **`socket_io_client` (Dart) caches sockets by URL.** `io.io('http://localhost:3000')` returned the cached socket authenticated as the previous user instead of creating a new connection with the new user's JWT token.
2. **`notifyListeners()` was not called after clearing state in `connect()`**, so the UI didn't immediately reflect the empty state.

**Fix applied (Round 10):**
- Added `enableForceNew()` to `SocketService.connect()` — forces a new socket connection every time, bypassing the internal cache
- Added defensive socket cleanup before creating new connections
- Added `notifyListeners()` after state clearing in `ChatProvider.connect()`

**Files modified:**
- `frontend/lib/services/socket_service.dart` — `enableForceNew()` + defensive cleanup
- `frontend/lib/providers/chat_provider.dart` — `notifyListeners()` after state clear

---

## 📑 TABLE OF CONTENTS

1. [📋 Quick Start](#-quick-start) — What is this, how to run
2. [🏗️ Architecture Overview](#️-architecture-overview) — Backend modules, frontend structure
3. [💾 Database Schema](#-database-schema) — All 4 tables with fields and constraints
4. [🔌 WebSocket Events Reference](#-websocket-events-reference) — Client→Server, Server→Client events
5. [🧭 Key Data Flows](#-key-data-flows) — Friend request, accept, auto-open chat, delete chat
6. [⚠️ Critical Gotchas](#️-critical-gotchas) — TypeORM relations, navigation, error handling
7. [📝 REST Endpoints](#-rest-endpoints) — Only 2 endpoints (register, login)
8. [🔐 Security Features](#-security-features) — CORS, rate limiting, validation, password strength
9. [🎯 Project Status](#-project-status) — Completed, in progress, remaining work
10. [🔍 Quick Reference](#-quick-reference---find-stuff-fast) — Find code fast (friend logic, WebSocket events, etc.)
11. [🧪 Environment Variables](#-environment-variables) — All required and optional vars
12. [📚 Frontend Architecture Details](#-frontend-architecture-details) — State management, navigation, responsive design, theme
13. [🚧 Known Limitations](#-known-limitations) — What this MVP doesn't have
14. [📋 Bug Fix History](#-bug-fix-history) — All fixes from Round 2–7, with root causes

---

## 📋 QUICK START

**What is this?** MVP 1-on-1 chat app: NestJS backend + Flutter frontend + PostgreSQL + Socket.IO WebSocket + JWT auth.

**Project structure:**
```
mvp-chat-app/
  backend/         # NestJS (API + WebSocket on :3000)
  frontend/        # Flutter (web, Android, iOS on :8080)
  docker-compose.yml
```

**Run locally:**
```bash
# Create .env with CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET
docker-compose up --build
# OR separately:
cd backend && npm run start:dev        # needs local PostgreSQL + .env
cd frontend && flutter run -d chrome
```

**⚠️ IMPORTANT:** Before running, ensure no other instances are running:
```bash
# Check for running Node.js processes
tasklist | grep -i node    # Windows
ps aux | grep node         # Linux/Mac

# Kill all Node.js if needed
taskkill //F //IM node.exe  # Windows
pkill node                  # Linux/Mac

# Verify only Docker backend is running
docker ps
netstat -ano | grep :3000
```

**Build:**
```bash
cd backend && npm run build && npm run lint
cd frontend && flutter build web
```

---

## 🏗️ ARCHITECTURE OVERVIEW

### Backend Modules (NestJS Monolith)

| Module | Purpose |
|--------|---------|
| **AuthModule** | POST /auth/register, POST /auth/login with JWT + bcrypt |
| **CloudinaryModule** | Avatar upload/delete to Cloudinary cloud storage |
| **UsersModule** | User entity, shared dependency |
| **FriendsModule** | Friend request system (PENDING/ACCEPTED/REJECTED) |
| **ConversationsModule** | 1-on-1 conversation linking two users (no duplicates via findOrCreate) |
| **MessagesModule** | Message entity with sender FK and conversation FK |
| **ChatModule** | Socket.IO gateway: real-time messaging + friend requests |

### Frontend Structure (Flutter + Provider)

| Component | Purpose |
|-----------|---------|
| **AuthProvider** | JWT lifecycle, token persistence via SharedPreferences, profile management |
| **ChatProvider** | WebSocket connection, conversations/messages state, socket events |
| **SettingsProvider** | Theme preference (system/light/dark, default dark) via SharedPreferences |
| **ConversationsScreen** | Main hub: mobile (list) or desktop (master-detail) at 600px breakpoint |
| **ChatDetailScreen** | Full chat view with message input |
| **FriendRequestsScreen** | Accept/reject pending requests, auto-navigate on accept |
| **NewChatScreen** | Send friend request by email |
| **SettingsScreen** | User settings: profile picture, active status, dark mode, password reset, account deletion |
| **RpgTheme** | Retro RPG color palette + Press Start 2P/Inter fonts |

---

## 💾 DATABASE SCHEMA

**PostgreSQL with TypeORM** (`synchronize: true` in dev)

```sql
users
  ├─ id (PK)
  ├─ email (unique)
  ├─ username (unique)
  ├─ password (bcrypt)
  ├─ profilePictureUrl (nullable) — full Cloudinary URL or legacy relative path
  ├─ profilePicturePublicId (nullable) — Cloudinary public_id for deletion
  ├─ activeStatus (boolean, default: true)
  └─ createdAt

conversations
  ├─ id (PK)
  ├─ user_one_id (FK → users)
  ├─ user_two_id (FK → users)
  └─ createdAt

messages
  ├─ id (PK)
  ├─ content
  ├─ sender_id (FK → users)
  ├─ conversation_id (FK → conversations, CASCADE DELETE)
  └─ createdAt

friend_requests
  ├─ id (PK)
  ├─ sender_id (FK → users, CASCADE DELETE)
  ├─ receiver_id (FK → users, CASCADE DELETE)
  ├─ status (enum: PENDING, ACCEPTED, REJECTED)
  ├─ createdAt
  ├─ respondedAt (nullable)
  └─ Index: (sender_id, receiver_id) — no unique constraint, allows resend after rejection
```

---

## 🔌 WebSocket Events Reference

### Client → Server

| Event | Payload | Response |
|-------|---------|----------|
| `sendMessage` | `{recipientId, content}` | `messageSent` (sender), `newMessage` (recipient) |
| `getMessages` | `{conversationId}` | `messageHistory` (last 50, oldest first) |
| `getConversations` | — | `conversationsList` (userOne/userTwo have `isOnline`) |
| `deleteConversation` | `{conversationId}` | Unfriends + `conversationsList` refreshed (both users) |
| `sendFriendRequest` | `{recipientEmail}` | `friendRequestSent` (sender), `newFriendRequest` + `pendingRequestsCount` (recipient). If mutual: auto-accept both |
| `acceptFriendRequest` | `{requestId}` | `friendRequestAccepted`, `conversationsList`, `friendsList`, `openConversation` (both users) |
| `rejectFriendRequest` | `{requestId}` | `friendRequestRejected`, `friendRequestsList`, `pendingRequestsCount` (receiver only) |
| `getFriendRequests` | — | `friendRequestsList`, `pendingRequestsCount` |
| `getFriends` | — | `friendsList` (each user has `isOnline`) |
| `unfriend` | `{userId}` | `unfriended` (both users), `conversationsList` refreshed |
| `updateActiveStatus` | `{activeStatus}` | `userStatusChanged` (to all friends) |

### Server → Client

`conversationsList` | `messageHistory` | `messageSent` | `newMessage` | `openConversation` | `error` | `newFriendRequest` | `friendRequestSent` | `friendRequestAccepted` | `friendRequestRejected` | `friendRequestsList` | `pendingRequestsCount` | `friendsList` | `unfriended` | `userStatusChanged`

**Connection:** Socket.IO with JWT token via query param `?token=xxx`. Server tracks online users via `Map<userId, socketId>`.

---

## 🧭 Key Data Flows

### Friend Request → Accept → Auto-Open Chat

1. **Send request:** User A emits `sendFriendRequest` with User B's email
2. **Receive request:** User B gets `newFriendRequest` + `pendingRequestsCount` badge updates
3. **Accept request:** User B clicks Accept → emits `acceptFriendRequest`
4. **Backend creates conversation** via `findOrCreate(sender, receiver)`
5. **Both users get events:**
   - `friendRequestAccepted`
   - `friendsList` (now includes each other)
   - `conversationsList` (new conversation appears)
   - `openConversation` with `{conversationId}` → triggers auto-navigate
6. **Frontend navigation:** `ChatProvider.onOpenConversation` sets `_pendingOpenConversationId` → screen's `build()` calls `consumePendingOpen()` → pops with conversationId → ConversationsScreen calls `_openChat()`

### Mutual Auto-Accept

When User A sends request to User B while User B already sent request to User A (before seeing A's):
- Backend detects reverse pending request in `sendRequest()`
- Auto-accepts BOTH directions
- Creates conversation via `findOrCreate()`
- Both users get `openConversation` → both auto-navigate

### Delete Chat = Unfriend

- Frontend calls `deleteConversation` event
- Backend now calls `friendsService.unfriend()` BEFORE deleting conversation
- Properly cleans up BOTH FriendRequest (ACCEPTED) AND Conversation + Messages
- Notifies other user with `unfriended` event
- Refreshes both users' conversations + friends lists

---

## ⚠️ CRITICAL GOTCHAS

### 1. TypeORM Relations — ALWAYS Explicit

**Problem:** Despite `eager: true` on entity, TypeORM does NOT reliably load relations.
**Rule:** Every `findOne()` and `find()` on `friendRequestRepository` MUST include `relations: ['sender', 'receiver']`.
**Without it:** `fr.sender` and `fr.receiver` are empty objects (only `id`, no `email`/`username`) → crashes in try/catch → silent failures.

**Files requiring this:**
- `backend/src/friends/friends.service.ts`: `sendRequest()`, `acceptRequest()`, `rejectRequest()`, `getPendingRequests()`, `getFriends()`

### 2. TypeORM .delete() Cannot Use Relation Conditions

**Problem:** `.delete()` generates simple SQL without JOINs → silently fails with nested relations.

**WRONG:**
```typescript
await repository.delete({
  sender: { id: userId1 },    // ❌ .delete() cannot resolve this
  receiver: { id: userId2 },
  status: 'accepted',
});
```

**RIGHT (find-then-remove pattern):**
```typescript
const records = await repository.find({
  where: [
    { sender: { id: userId1 }, receiver: { id: userId2 }, status: 'accepted' },
    { sender: { id: userId2 }, receiver: { id: userId1 }, status: 'accepted' },
  ],
});
if (records.length > 0) {
  await repository.remove(records);  // ✅ deletes by primary key
}
```

### 3. Navigation from Provider

**Problem:** `ChatProvider.onOpenConversation` fires in provider (not widget tree) → cannot call `Navigator.push()` from there.
**Solution:** Use reactive `consumePendingOpen()` pattern:
- Provider sets `_pendingOpenConversationId` + calls `notifyListeners()`
- Screen's `build()` calls `consumePendingOpen()` to get ID
- Screen calls `Navigator.pop(conversationId)` via `addPostFrameCallback`

**Screens using this:** `FriendRequestsScreen`, `NewChatScreen`

### 4. Single Try/Catch Masks Errors

**Problem:** `handleAcceptFriendRequest` has one try/catch for entire handler → if ANY step fails, ALL subsequent emits skipped.
**Impact:** Users get silent failures (no friends added, chat doesn't open).
**Solution:** Wrap individual operations separately, emit partial success where possible.

### 5. Multiple Backend Instances (DEBUGGING)

**Problem:** Frontend shows different data than backend logs suggest.
**Root cause:** Multiple backend instances running on same port (Docker + local).

**How to detect:**
- Frontend logs show userId X connecting
- Backend logs show NO connection from userId X
- Check running processes: `tasklist | grep -i node` or `ps aux | grep node`
- Check port ownership: `netstat -ano | grep :3000`

**How to fix:**
- Kill all local Node.js processes before testing
- Use `docker-compose down` then `docker-compose up` to ensure clean state
- Verify only ONE backend is running: `docker ps` and `netstat -ano | grep LISTENING`

**Warning signs:**
- Database shows 0 conversations but frontend receives "1 conversation"
- Backend validation works ("You can only message friends") but getConversations() returns wrong data
- Changes to code don't appear in running app (connecting to old instance)

### 6. Socket.IO Client Caches Sockets by URL (Dart)

**Problem:** `socket_io_client` Dart package caches socket instances by URL. Calling `io.io(url, newOptions)` after `disconnect()`/`dispose()` can return a cached socket with old auth credentials.
**Rule:** ALWAYS use `enableForceNew()` in OptionBuilder when the same URL may be reused with different JWT tokens (e.g., after logout/login).
**File:** `frontend/lib/services/socket_service.dart`

### 7. Other Key Points

- `deleteConversation` NOW calls `unfriend()` → both delete conversation AND break friendship
- `friendRequestRejected` sent ONLY to receiver (silent rejection)
- No unique constraint on (sender_id, receiver_id) — intentional, allows resend after rejection
- Mutual requests auto-accept BOTH directions (check reverse pending in `sendRequest()`)
- `unfriend()` deletes ONLY ACCEPTED requests, not pending/rejected
- Badge count: fetched on connect, updated via `pendingRequestsCount` events
- `FriendRequestsScreen` emits `getFriendRequests` in initState → aware of double-emits if revisited

---

## 📝 REST Endpoints

**Authentication (2 endpoints):**

| Endpoint | Body | Response |
|----------|------|----------|
| POST /auth/register | `{email, username, password}` | `{id, email, username}` |
| POST /auth/login | `{email, password}` | `{access_token}` |

**User Management (4 endpoints, all require JWT auth):**

| Endpoint | Method | Body | Response |
|----------|--------|------|----------|
| /users/profile-picture | POST | `multipart/form-data {file}` | `{profilePictureUrl}` (Cloudinary URL) |
| /users/reset-password | POST | `{oldPassword, newPassword}` | `200 OK` |
| /users/account | DELETE | `{password}` | `200 OK` |
| /users/active-status | PATCH | `{activeStatus}` | `200 OK` |

**All chat operations use WebSocket.**

**Password rules:** Min 8 chars, uppercase + lowercase + number (enforced via `validatePassword()`)

---

## 🔐 Security Features

✅ **CORS:** Uses `ALLOWED_ORIGINS` env var (default: `http://localhost:3000`)
✅ **Rate limiting:** Login 5/15min, Register 3/hour, Profile picture upload 10/hour
✅ **WebSocket validation:** All handlers validate input via DTOs
✅ **Env var validation:** Startup fails if JWT_SECRET or critical DB vars missing
✅ **Password strength:** 8+ chars + uppercase + lowercase + number
✅ **File upload security:** Only JPEG/PNG images allowed, max 5MB
✅ **JWT authentication:** All user management endpoints require JWT auth

---

## 🎯 PROJECT STATUS

### Completed (2026-01-30)

✅ **Issue #1-5: Critical Security Fixes**
- CORS hardening, env validation, password strength, rate limiting, WebSocket input validation

✅ **Issue #6: NestJS Logger**
- Replaced 50+ console.log statements with structured Logger

✅ **Issue #9: Mapper Classes**
- Extracted UserMapper, ConversationMapper, FriendRequestMapper → ~50 lines eliminated

✅ **Issue #10: Message Pagination**
- Added limit/offset parameters to `MessagesService.findByConversation()` (default: 50, 0)
- Updated GetMessagesDto with optional limit and offset fields
- Updated ChatGateway.handleGetMessages() to pass pagination params
- Added SocketService.getMessages() optional parameters
- Added ChatProvider.loadMoreMessages() method for incremental loading
- Messages now support pagination via WebSocket

✅ **Issue #7: Individual Error Handling**
- Refactored `handleAcceptFriendRequest()` with 6 separate try/catch blocks
- Refactored `handleSendFriendRequest()` with individual error handling for auto-accept and pending flows
- Refactored `handleUnfriend()` with 5 separate try/catch blocks
- Critical operations (acceptRequest, sendRequest, unfriend) fail fast with error emit
- Non-critical operations (emit events, refresh lists) continue on failure with error logging
- Partial success now possible - users get some updates even if later operations fail
- Improved error messages distinguish critical vs non-critical failures

✅ **Issue #8: Split Gateway into Service Classes**
- Created `ChatMessageService` — handles sendMessage, getMessages (2 handlers)
- Created `ChatFriendRequestService` — handles 6 friend request handlers (send, accept, reject, get, getFriends, unfriend)
- Created `ChatConversationService` — handles 3 conversation handlers (start, get, delete)
- Refactored `chat.gateway.ts` from 864 lines to 195 lines (77% reduction)
- Gateway now only handles WebSocket connection/disconnection and delegates to services
- All business logic moved to service classes for better testability and maintainability
- Services injected via constructor, receive server and onlineUsers Map as parameters

✅ **User Settings Feature (Phase 1 & 2 - 2026-01-31)**
**Backend (Phase 1 + Cloudinary 2026-02-01):**
- Added `profilePictureUrl` (varchar, nullable), `profilePicturePublicId` (nullable), `activeStatus` (boolean, default: true) to users table
- Created `UsersController` with 4 new REST endpoints (profile picture, reset password, delete account, active status)
- Created 3 new DTOs: `ResetPasswordDto`, `DeleteAccountDto`, `UpdateActiveStatusDto`
- Profile pictures: Multer memoryStorage → Cloudinary upload (JPEG/PNG only, max 5MB)
- CloudinaryModule + CloudinaryService for upload/delete
- Updated `AuthService.login()` to include `profilePictureUrl` and `activeStatus` in JWT payload (2026-02-01: activeStatus in JWT; isOnline in friends/conversations payloads)
- Updated `JwtStrategy.validate()` to extract new user fields from JWT (including activeStatus)
- Added WebSocket handler `updateActiveStatus` in `ChatFriendRequestService` → broadcasts `userStatusChanged` to all friends
- Updated `UserMapper.toPayload()` to include `profilePictureUrl` and `activeStatus`
- npm packages: `multer`, `@types/multer`, `@nestjs/platform-express`

**Frontend (Phase 2):**
- Updated `UserModel` with `profilePictureUrl`, `activeStatus`, and `isOnline` (bool?) + `copyWith()` method
- Created `SettingsProvider` for dark mode preference persistence (system/light/dark)
- Updated `AuthProvider` with 3 new methods: `updateProfilePicture()`, `resetPassword()`, `deleteAccount()`
- Updated `AuthProvider.logout()` to preserve dark mode preference after logout
- Updated `ChatProvider` with `socket` getter to expose `SocketService`
- Added `ChatProvider.onUserStatusChanged()` listener to update friends' active status in real-time
- Updated `ApiService` with 4 new methods matching backend endpoints
- Updated `SocketService` with `updateActiveStatus()` emit and `userStatusChanged` listener
- Completely redesigned `SettingsScreen` with 6 tiles: profile header, active status toggle, dark mode dropdown, privacy (coming soon), devices, reset password, delete account, logout button
- Rewrote `AvatarCircle` as `StatefulWidget` with profile picture support, fallback to gradient, online indicator (green/grey dot), loading state
- Created 3 new dialogs: `ResetPasswordDialog`, `DeleteAccountDialog`, `ProfilePictureDialog` (camera vs gallery)
- Updated `main.dart` to include `SettingsProvider` in `MultiProvider` and consume dark mode preference
- Flutter packages: `image_picker: ^1.1.2`, `device_info_plus: ^11.5.0`

---

## 🔍 QUICK REFERENCE - Find Stuff Fast

### Modify friend request logic
- Backend core logic: `backend/src/friends/friends.service.ts` (9 methods)
- Backend WebSocket handlers: `backend/src/chat/services/chat-friend-request.service.ts` (6 handlers)
- Gateway delegation: `backend/src/chat/chat.gateway.ts` (delegates to service)

### Modify message logic
- Backend core logic: `backend/src/messages/messages.service.ts`
- Backend WebSocket handlers: `backend/src/chat/services/chat-message.service.ts` (2 handlers)
- Gateway delegation: `backend/src/chat/chat.gateway.ts`

### Modify conversation logic
- Backend core logic: `backend/src/conversations/conversations.service.ts`
- Backend WebSocket handlers: `backend/src/chat/services/chat-conversation.service.ts` (3 handlers)
- Gateway delegation: `backend/src/chat/chat.gateway.ts`

### Add new WebSocket event
1. Add business logic in appropriate service (`chat-message.service.ts`, `chat-friend-request.service.ts`, or `chat-conversation.service.ts`)
2. Add handler method in the service (receives client, data, server, onlineUsers)
3. Add delegation in `backend/src/chat/chat.gateway.ts` with `@SubscribeMessage` decorator
4. Add listener in `frontend/lib/services/socket_service.dart` (socket.on() in connect())
5. Add callback in `frontend/lib/providers/chat_provider.dart`

### Change badge appearance
- `frontend/lib/screens/conversations_screen.dart` (search "Stack" for badge UI)

### Modify friend request UI
- `frontend/lib/screens/friend_requests_screen.dart` (entire screen)

### Add database column to FriendRequest
1. Edit `backend/src/friends/friend-request.entity.ts`
2. Add field to `FriendRequestModel` in `frontend/lib/models/friend_request_model.dart`
3. TypeORM auto-migrates if `synchronize: true`

### Modify auto-open chat after accept
- Backend emit: `backend/src/chat/chat.gateway.ts` → `handleAcceptFriendRequest`
- Frontend monitor: `frontend/lib/screens/friend_requests_screen.dart` → `consumePendingOpen()` in `build()`
- Navigation: `frontend/lib/screens/conversations_screen.dart` → `_openFriendRequests()` awaits result

### Debug friend authorization
- Backend logs: Search for `acceptFriendRequest:` in console
- Logic: `backend/src/friends/friends.service.ts` → `areFriends()`

### Modify unfriend logic
- Delete logic: `backend/src/friends/friends.service.ts` → `unfriend()` (TWO separate deletes for bidirectional)
- Gateway orchestration: `backend/src/chat/chat.gateway.ts` → `handleUnfriend()`
- Conversation cleanup: `backend/src/conversations/conversations.service.ts` → `delete()`

### Modify settings screen
- UI and layout: `frontend/lib/screens/settings_screen.dart`
- Dialogs: `frontend/lib/widgets/dialogs/` (reset_password_dialog, delete_account_dialog, profile_picture_dialog)
- Avatar with profile picture: `frontend/lib/widgets/avatar_circle.dart` — handles absolute URLs (Cloudinary) and relative paths via `_buildImageUrl()`

### Modify avatar storage (Cloudinary)
- Service: `backend/src/cloudinary/cloudinary.service.ts` — uploadAvatar(), deleteAvatar()
- Controller: `backend/src/users/users.controller.ts` — uploadProfilePicture uses memoryStorage + CloudinaryService

### Add new user management endpoint
1. Add method to `backend/src/users/users.service.ts`
2. Add endpoint to `backend/src/users/users.controller.ts` with `@UseGuards(JwtAuthGuard)`
3. Add method to `frontend/lib/services/api_service.dart`
4. Add method to `frontend/lib/providers/auth_provider.dart`
5. Call from `frontend/lib/screens/settings_screen.dart`

---

## 🧪 ENVIRONMENT VARIABLES

**Backend (.env or docker-compose):**

| Var | Default | Required | Purpose |
|-----|---------|----------|---------|
| `DB_HOST` | localhost | ✓ | PostgreSQL host |
| `DB_PORT` | 5432 | ✓ | PostgreSQL port |
| `DB_USER` | postgres | ✓ | PostgreSQL user |
| `DB_PASS` | postgres | ✓ | PostgreSQL password |
| `DB_NAME` | chat_db | ✓ | Database name |
| `JWT_SECRET` | (none) | ✓ | JWT signing key — startup fails if missing |
| `CLOUDINARY_CLOUD_NAME` | (none) | ✓ | Cloudinary cloud name |
| `CLOUDINARY_API_KEY` | (none) | ✓ | Cloudinary API key |
| `CLOUDINARY_API_SECRET` | (none) | ✓ | Cloudinary API secret |
| `NODE_ENV` | development | — | Affects database `synchronize` and logging |
| `PORT` | 3000 | — | Backend server port |
| `ALLOWED_ORIGINS` | http://localhost:3000 | — | CORS origins (comma-separated) |

**Frontend:**
- `BASE_URL` dart define (defaults to `http://localhost:3000`, important for Docker/nginx)

---

## 📚 FRONTEND ARCHITECTURE DETAILS

### State Management (Provider Pattern)

- **AuthProvider:** JWT lifecycle → login → decode JWT → save to SharedPreferences → auto-restore on app start (checks expiry). User management methods: `updateProfilePicture()`, `resetPassword()`, `deleteAccount()`
- **ChatProvider:** WebSocket connection → listen to all events → manage state. Key methods:
  - `openConversation(conversationId)` — clears messages, fetches history
  - `consumePendingOpen()` — returns and clears `_pendingOpenConversationId` for navigation
  - `socket` getter — exposes `SocketService` for direct WebSocket operations (e.g., `updateActiveStatus()`)
- **SettingsProvider:** Dark mode preference (system/light/dark) → saved to SharedPreferences → survives logout

### Navigation

```
main.dart → AuthGate (watches AuthProvider.isLoggedIn)
  ├─ false → AuthScreen (login/register)
  └─ true → ConversationsScreen (main hub)
      ├─ Mobile (<600px): Navigator.push → ChatDetailScreen
      ├─ Desktop (≥600px): side-by-side (list + embedded chat)
      ├─ FriendRequestsScreen: push, await return value (conversationId or null)
      └─ NewChatScreen: push, await return value (conversationId or null)
```

### Responsive Design

- **Breakpoint:** 600px width (use `LayoutBuilder`)
- **Mobile:** Push navigation between screens
- **Desktop:** Master-detail layout (list + embedded chat)
- **Safety:** All screens use `SafeArea` for notches/gesture bars

### Theme System

- **Light/Dark:** `RpgTheme.themeDataLight` (light) and `RpgTheme.themeData` (dark). main.dart uses theme/themedataLight and darkTheme/themedata; ThemeMode from SettingsProvider (default preference: dark).
- **Colors:** RPG palette dark (background #0A0A2E, gold #FFCC00, purple #7B7BF5); light palette (backgroundLight, boxBgLight, textColorLight, etc.) for themeDataLight.
- **Fonts:**
  - `pressStart2P()` — retro font for titles/headers/logos ONLY
  - `bodyFont()` — readable Inter font for body text, messages, form fields
- **Spacing:** 8px for inputs, 16px for message bubbles

### Dependencies

**Frontend:**
```yaml
provider: ^6.1.2                    # State management
socket_io_client: ^2.0.3+1          # WebSocket
http: ^1.2.2                        # REST
jwt_decoder: ^2.0.1                 # JWT parsing
shared_preferences: ^2.3.4          # Token persistence
google_fonts: ^6.2.1                # Press Start 2P + Inter
image_picker: ^1.1.2                # Profile picture from camera/gallery
device_info_plus: ^11.5.0           # Device name for settings screen
```

**Backend:**
```
cloudinary                          # Cloud storage for avatars
multer                              # File upload middleware (memoryStorage)
@types/multer                       # TypeScript types for multer
@nestjs/platform-express            # Express platform for NestJS
```

---

## 🚧 KNOWN LIMITATIONS

- ❌ No user search/discovery — must know exact email to send friend request
- ✅ User profiles: profile pictures, active status, password reset, account deletion
- ❌ No typing indicators, read receipts, message editing/deletion
- ✅ Message pagination supported (limit/offset params, default 50 messages)
- ❌ No last message in `conversationsList` — track client-side
- ❌ No database unique constraint on user pair (deduplication in `findOrCreate`)
- ❌ No unique constraint on (sender, receiver) in friend_requests (intentional, allows resend)
- ✅ Profile pictures stored in Cloudinary (free tier, CDN, works on web + mobile)

---

## 📋 BUG FIX HISTORY

### 2026-01-31 (Round 10) - Socket Cache Causing Session Data Leakage (FINAL FIX)

**Problem:** After logout → login as different user, the new user saw conversations/friends from the previously logged-in user. Data disappeared after page refresh.

**Root cause:** The `socket_io_client` Dart library internally caches socket instances by URL. When `io.io('http://localhost:3000', options)` was called for user B after user A logged out, the library returned the **cached socket still authenticated with user A's JWT token**. The backend verified the old token and returned user A's data.

**Contributing factor:** A `dartvm.exe` (Flutter dev server) process was also running on port 8080, conflicting with the Docker nginx frontend on the same port. The browser connected to the dev server (serving old code without the fix) instead of Docker.

**Fix:**
1. Added `enableForceNew()` to `SocketService.connect()` OptionBuilder — forces a completely new socket connection, bypassing the internal cache
2. Added defensive socket cleanup (`disconnect()` + `dispose()`) at the start of `SocketService.connect()` before creating a new socket
3. Added `notifyListeners()` after clearing state in `ChatProvider.connect()` so UI immediately shows empty state

**Files modified:**
- `frontend/lib/services/socket_service.dart` — `enableForceNew()` + defensive cleanup
- `frontend/lib/providers/chat_provider.dart` — `notifyListeners()` after state clear

**Lesson learned:**
- `socket_io_client` in Dart caches sockets by URL — ALWAYS use `enableForceNew()` when reconnecting with different credentials
- Always check for conflicting processes on the same port (`netstat -ano | findstr :PORT`, `tasklist | findstr PID`)
- DDC module loader in browser console = debug build from `flutter run`, not Docker release build

**Testing:**
- ✅ Login user A → logout → login user B → user B sees empty state (correct)
- ✅ Backend logs confirm user B connects as user B (not user A)
- ✅ Page refresh no longer needed to see correct data

### 2026-01-31 (Round 9) - Multiple Backend Instances (DEBUGGING LESSON)

**Problem:** After implementing Round 8 fix, testing showed that new users STILL saw conversations/friends from previous users.

**Root cause (UNEXPECTED):** Two backend instances running simultaneously:
1. **Docker backend** (port 3000) - with all fixes, monitored in logs
2. **Local backend** (port 3000) - old code via `npm run start:dev`, WITHOUT fixes

**Why this happened:**
- User had started local backend during development
- Later started Docker backend on same port
- Windows port binding allowed both to coexist (Docker proxy)
- Frontend connected to **local backend** (old buggy code)
- Developer monitored **Docker backend** logs (correct code, but no connections!)

**Symptoms that revealed the issue:**
- Frontend logs showed userId: 111 (ziomek71) connecting
- Backend (Docker) logs showed NO connection from userId: 111
- Backend correctly validated "You can only message friends" for user 111
- But `getConversations()` and `getFriends()` returned wrong data
- Database queries showed user 111 had ZERO conversations
- Yet frontend received "1 conversation, 1 friend"

**How it was discovered:**
1. Added detailed logging to `ConversationsService.findByUser()` and `FriendsService.getFriends()`
2. Logs showed Docker backend NEVER received connections from new users
3. Checked running processes: multiple `node.exe` instances found
4. Killed all local Node.js processes → problem disappeared

**Fix:**
```bash
# Kill all local Node.js processes
tasklist | grep -i "node.exe" | awk '{print $2}' | xargs -I {} taskkill //F //PID {}
```

**Files modified:**
- None (code was already correct in Docker backend)

**Lesson learned:**
- ✅ **ALWAYS check for multiple instances of the same service**
- ✅ When frontend shows different data than backend logs, suspect connection to wrong backend
- ✅ Use `netstat -ano` to verify which process owns which port
- ✅ When testing fixes, ensure old dev servers are stopped before starting new ones
- ✅ Docker port 3000 → host 3000 can coexist with local :3000, causing confusion

**Testing:**
- ✅ After killing local backends, new users see empty conversations list
- ✅ Frontend connects to Docker backend (verified in logs)
- ✅ Session isolation works correctly

### 2026-01-31 (Round 8) - Session Data Leakage Fix (CRITICAL)

**Problem:** After logout → register new user → login, the new user saw conversations/friends of the previously logged-out user.

**Root cause:** Race condition between two postFrameCallbacks:
1. AuthGate detects login transition → schedules `chat.disconnect()` in postFrameCallback
2. ConversationsScreen.initState() → schedules `chat.connect()` in postFrameCallback
3. **Order of execution is NOT guaranteed** - if `connect()` runs before `disconnect()`, old data persists
4. Even worse: `connect()` would fetch new user's data, then `disconnect()` would clear it

**Fix:**
1. **ChatProvider.connect()** (line 76-88) - ALWAYS clear ALL state variables at the very start:
   - Clears conversations, messages, friends, friend requests, last messages, flags
   - This happens BEFORE any socket operations
   - Prevents race condition - state is clean regardless of postFrameCallback order
   - Old socket cleanup happens after state clear

2. **AuthGate** (line 54-62) - Changed to also clear on logout transition (true → false):
   - Detects when user logs out and calls `chat.disconnect()` for extra safety
   - Guarantees clean state when returning to login screen

**Files modified:**
- `frontend/lib/providers/chat_provider.dart` - Added state clearing at start of connect()
- `frontend/lib/main.dart` - AuthGate now clears on logout too

**Why this works:**
- No matter what order postFrameCallbacks execute, `connect()` ALWAYS starts with clean state
- Even if `disconnect()` never runs, `connect()` handles cleanup itself
- Defense in depth: both logout detection AND connect() clear state

**Testing:**
- ✅ Logout user A → register user B → login user B → verify clean state (no A's data)
- ✅ Refresh page after logout → old user data disappears immediately

### 2026-01-30 (Round 7) - Logger + Mappers

**Issue #6: Replace console.log with NestJS Logger** ✅
- 50+ console.log → Logger.debug()
- Files: `chat.gateway.ts`, `friends.service.ts`, `main.ts`
- Commit: c7eb7e6

**Issue #9: Extract Mapper Classes** ✅
- Created: `UserMapper`, `ConversationMapper`, `FriendRequestMapper`
- Eliminated: ~50 lines of repetitive code
- Handlers refactored: `handleGetConversations` 7 → 1 line, etc.
- Commit: 84e9a36

### 2026-01-30 (Round 6) - Critical Security Fixes

**All 5 critical issues resolved:**

1. **CORS:** From `'*'` → `ALLOWED_ORIGINS` env var
2. **Env validation:** Created `env.validation.ts`, fails on startup if critical vars missing
3. **Password:** Min 8 chars + uppercase + lowercase + number
4. **Rate limiting:** Login 5/15min, Register 3/hour via @nestjs/throttler
5. **WebSocket input:** 8 DTOs + validation in all handlers

Commit: b9edc3b, docs: 02720c8

### 2026-01-30 (Round 5) - "Already Friends" Bug After Delete Chat

**Problem:** Delete chat → new friend request → "Already friends" error
**Root cause:** `deleteConversation` only deleted Conversation, not FriendRequest (ACCEPTED)
**Fix:** `deleteConversation` now calls `friendsService.unfriend()` first
**Impact:** Both actions now properly clean up friendship + conversation + messages

### 2026-01-30 (Round 4) - Unfriend Bugs

**Problem:** Unfriend didn't delete, re-invitation blocked
**Root cause:** `.delete()` cannot resolve relation conditions (TypeORM limitation)
**Fix:** Replaced with find-then-remove pattern (`.find()` + `.remove()`)

### 2026-01-30 (Round 3) - Auto-Open Chat + Relations

**Problem:** Friend requests didn't work, chat didn't auto-open
**8 root causes found:**
1. Missing `relations: ['sender', 'receiver']` in `getFriends()` → crashed accept handler
2. Same issue in `getPendingRequests()` and `sendRequest()`
3. Auto-accept didn't create conversation
4. No `pendingRequestsCount` update
5. No `openConversation` event
6. Frontend didn't monitor `consumePendingOpen()`
7. ConversationsScreen didn't await navigation result
8. FriendRequestsScreen didn't navigate

**Fixed all 8.**

### 2026-01-30 (Round 2) - Friend Requests System

5 bugs fixed:
1. Missing relations in `acceptRequest()` and `rejectRequest()`
2. Missing `friendsList` events in `handleAcceptFriendRequest()`
3. Mutual auto-accept not emitting events
4. Frontend not requesting friends list update
5. Consistency fixes

---

## ✨ CODE QUALITY NOTES

**Strengths:**
- Clean NestJS module separation (Auth, Users, Friends, Chat, Conversations, Messages)
- Correct TypeORM patterns (eager loading, relations, find-then-remove)
- Solid Provider pattern in Flutter (two focused providers)
- Responsive design (master-detail on desktop, stacked on mobile)
- Comprehensive WebSocket events (14+ handlers)
- Clever reactive navigation pattern (`consumePendingOpen()`)

**Current issues (lower priority):**
- No test coverage (zero tests currently)
- Magic numbers scattered (500ms delay, 600px breakpoint)
- Could use database indexes on frequently-queried columns
- Consider adding WebSocket reconnection logic in frontend

---

**MAINTAIN THIS FILE. Future agents depend on it.** ✅
