# CLAUDE.md - MVP Chat App Knowledge Base

**Last updated:** 2026-01-30

**MANDATORY RULE: Keep This File Up To Date**

**After EVERY code change (bug fix, new feature, refactor, config change), update this file immediately.** This is the single source of truth for future agents.A future agent must be able to read ONLY this file and understand the current state of the project without reading every source file

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
docker-compose up --build
# OR separately:
cd backend && npm run start:dev        # needs local PostgreSQL
cd frontend && flutter run -d chrome
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
| **SettingsProvider** | Dark mode preference persistence via SharedPreferences |
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
  ├─ profilePictureUrl (nullable)
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
| `getConversations` | — | `conversationsList` |
| `deleteConversation` | `{conversationId}` | Unfriends + `conversationsList` refreshed (both users) |
| `sendFriendRequest` | `{recipientEmail}` | `friendRequestSent` (sender), `newFriendRequest` + `pendingRequestsCount` (recipient). If mutual: auto-accept both |
| `acceptFriendRequest` | `{requestId}` | `friendRequestAccepted`, `conversationsList`, `friendsList`, `openConversation` (both users) |
| `rejectFriendRequest` | `{requestId}` | `friendRequestRejected`, `friendRequestsList`, `pendingRequestsCount` (receiver only) |
| `getFriendRequests` | — | `friendRequestsList`, `pendingRequestsCount` |
| `getFriends` | — | `friendsList` |
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

### 5. Other Key Points

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
| /users/profile-picture | POST | `multipart/form-data {file}` | `{profilePictureUrl}` |
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
**Backend (Phase 1):**
- Added `profilePictureUrl` (varchar, nullable) and `activeStatus` (boolean, default: true) columns to users table
- Created `UsersController` with 4 new REST endpoints (profile picture, reset password, delete account, active status)
- Created 3 new DTOs: `ResetPasswordDto`, `DeleteAccountDto`, `UpdateActiveStatusDto`
- Configured Multer for file upload: JPEG/PNG only, max 5MB, stored in `./uploads/profiles/`
- Added static file serving in `main.ts` at `/uploads/` prefix
- Added Docker volume mount: `./backend/uploads:/app/uploads`
- Updated `AuthService.login()` to include `profilePictureUrl` and `activeStatus` in JWT payload
- Updated `JwtStrategy.validate()` to extract new user fields from JWT
- Added WebSocket handler `updateActiveStatus` in `ChatFriendRequestService` → broadcasts `userStatusChanged` to all friends
- Updated `UserMapper.toPayload()` to include `profilePictureUrl` and `activeStatus`
- npm packages: `multer`, `@types/multer`, `@nestjs/platform-express`

**Frontend (Phase 2):**
- Updated `UserModel` with `profilePictureUrl` and `activeStatus` fields + `copyWith()` method
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
- Avatar with profile picture: `frontend/lib/widgets/avatar_circle.dart`

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

- **Colors:** RPG palette (background #0A0A2E, gold #FFCC00, purple #7B7BF5, border #4A4AE0)
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
multer                              # File upload middleware
@types/multer                       # TypeScript types for multer
@nestjs/platform-express            # Express platform for NestJS (static files)
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
- ❌ Profile pictures stored locally in `./uploads/` (not cloud storage like S3)

---

## 📋 BUG FIX HISTORY

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
