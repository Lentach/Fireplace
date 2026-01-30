# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

MVP 1-on-1 chat application. NestJS backend + Flutter frontend + PostgreSQL + WebSocket (Socket.IO) + JWT auth + Docker.

## Project Structure

```
mvp-chat-app/
  backend/         # NestJS app (API + WebSocket)
  frontend/        # Flutter app (web, Android, iOS)
  docker-compose.yml
  README.md
  CLAUDE.md
```

## Commands

### Backend
```bash
cd backend
npm run build          # Compile TypeScript
npm run start:dev      # Run with hot-reload (needs local PostgreSQL)
npm run start          # Run compiled version
npm run lint           # ESLint
```

### Frontend
```bash
cd frontend
flutter pub get        # Install dependencies
flutter run -d chrome  # Run in Chrome (dev mode, backend on :3000)
flutter build web      # Build for production
```

### Docker (recommended)
```bash
docker-compose up --build   # Run PostgreSQL + backend + frontend
# Backend: http://localhost:3000
# Frontend: http://localhost:8080
```

## Architecture

**Backend — Monolith NestJS app** with these modules:

- `AuthModule` — registration (POST /auth/register) and login (POST /auth/login) with JWT. Uses Passport + bcrypt.
- `UsersModule` — User entity and service. Shared dependency for Auth, Chat, Friends.
- `FriendsModule` — **NEW** Friend request system. FriendRequest entity + FriendsService with authorization logic.
- `ConversationsModule` — Conversation entity linking two users. findOrCreate pattern prevents duplicates.
- `MessagesModule` — Message entity with content, sender, conversation FK.
- `ChatModule` — WebSocket Gateway (Socket.IO). Handles real-time messaging + friend requests. Verifies JWT on connection via query param `?token=`.

**Frontend — Flutter app** with Provider state management:

- `providers/auth_provider.dart` — JWT token, login/register/logout, persists token via SharedPreferences.
- `providers/chat_provider.dart` — conversations list, messages, active conversation, **friend requests, pending count, friends list**, socket events.
- `services/api_service.dart` — REST calls to /auth/register, /auth/login.
- `services/socket_service.dart` — Socket.IO wrapper for real-time events **+ friend request events**.
- `screens/auth_screen.dart` — Login/register UI with RPG title, modern Material form.
- `screens/conversations_screen.dart` — Main hub: conversation list (mobile) or master-detail (desktop ≥600px). **Has friend request badge with red counter**.
- `screens/chat_detail_screen.dart` — Full chat view with messages and input bar. Used standalone (mobile) or embedded (desktop). **Has unfriend PopupMenu button**.
- `screens/new_chat_screen.dart` — **NEW FLOW**: Send friend request by email (was "start conversation").
- `screens/friend_requests_screen.dart` — **NEW** Full screen for managing pending friend requests. Accept/reject buttons.
- `models/friend_request_model.dart` — **NEW** FriendRequest model with fromJson parsing.
- `theme/rpg_theme.dart` — Colors, ThemeData, `pressStart2P()` for titles, `bodyFont()` (Inter) for body text.

**Data flow for friend requests:**
1. User A emits `sendFriendRequest` with recipient email → Backend checks if mutual request exists (if yes: auto-accept both) → Creates pending FriendRequest → User B gets `newFriendRequest` event + badge count updates.
2. User B emits `acceptFriendRequest` with request ID → Status changes to ACCEPTED → Both users get `friendRequestAccepted` event → Can now message each other.

**Data flow for sending a message:**
User checks `areFriends(senderId, recipientId)` via ChatGateway → If false: emit error "You must be friends" → If true: finds/creates conversation → saves message → emits `newMessage` to recipient + `messageSent` to sender.

**WebSocket events (original):** `sendMessage`, `getMessages`, `getConversations`, `newMessage`, `messageSent`, `messageHistory`, `conversationsList`, `deleteConversation`.

**WebSocket events (new - friend requests):** `sendFriendRequest`, `acceptFriendRequest`, `rejectFriendRequest`, `getFriendRequests`, `getFriends`, `unfriend`, `newFriendRequest`, `friendRequestSent`, `friendRequestAccepted`, `friendRequestRejected`, `friendRequestsList`, `pendingRequestsCount`, `friendsList`, `unfriended`.

## Database

PostgreSQL with TypeORM. `synchronize: true` auto-creates tables (dev only).
Four tables: `users`, `conversations`, `messages`, `friend_requests` (new).

**Tables:**
- `users`: id, email (unique), username (unique), password (bcrypt), createdAt
- `conversations`: id, user_one_id (FK), user_two_id (FK), createdAt
- `messages`: id, content, sender_id (FK), conversation_id (FK), createdAt
- `friend_requests`: id, sender_id (FK), receiver_id (FK), status (enum: pending/accepted/rejected), createdAt, respondedAt

## Environment variables

`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME`, `JWT_SECRET`, `PORT` — all have defaults for local dev.

Frontend uses `BASE_URL` dart define (defaults to `http://localhost:3000`). In Docker, nginx proxies API/WebSocket requests to the backend.

## Backend API Reference

### REST Endpoints (only 2 exist)
- `POST /auth/register` — Body: `{email, username, password}` → Returns `{id, email, username}`. Password min 6 chars. Username must be unique. ConflictException if email or username exists.
- `POST /auth/login` — Body: `{email, password}` → Returns `{access_token}`. UnauthorizedException on bad creds.

**There are NO other REST endpoints.** All chat operations use WebSocket.

### WebSocket Events

#### Messaging (original)
| Client → Server | Payload | Response Event |
|-----------------|---------|----------------|
| `sendMessage` | `{recipientId: int, content: string}` | `messageSent` to sender, `newMessage` to recipient |
| `startConversation` | `{recipientEmail: string}` | `conversationsList` + `openConversation` to sender |
| `getMessages` | `{conversationId: int}` | `messageHistory` (last 50 messages, oldest first) |
| `getConversations` | (no payload) | `conversationsList` |
| `deleteConversation` | `{conversationId: int}` | `conversationsList` (refreshed list) |

#### Friend Requests (NEW)
| Client → Server | Payload | Response Event |
|-----------------|---------|----------------|
| `sendFriendRequest` | `{recipientEmail: string}` | `friendRequestSent` to sender, `newFriendRequest` to recipient (if online) |
| `acceptFriendRequest` | `{requestId: int}` | `friendRequestAccepted` to both, `conversationsList` refreshed for both |
| `rejectFriendRequest` | `{requestId: int}` | `friendRequestRejected` to receiver, `friendRequestsList` refreshed |
| `getFriendRequests` | (no payload) | `friendRequestsList` + `pendingRequestsCount` |
| `getFriends` | (no payload) | `friendsList` |
| `unfriend` | `{userId: int}` | `unfriended` to both, `conversationsList` refreshed for both |

#### Server → Client Responses

**Messaging:**
| Event | Payload |
|-------|---------|
| `conversationsList` | `ConversationModel[]` |
| `messageHistory` | `MessageModel[]` |
| `messageSent` | `MessageModel` (confirmation) |
| `newMessage` | `MessageModel` (incoming from other user) |
| `openConversation` | `{conversationId: int}` |
| `error` | `{message: string}` |

**Friend Requests:**
| Event | Payload |
|-------|---------|
| `newFriendRequest` | `FriendRequestModel` (sender, receiver, status, timestamps) |
| `friendRequestSent` | `FriendRequestModel` (confirmation) |
| `friendRequestAccepted` | `FriendRequestModel` (to both users) |
| `friendRequestRejected` | `FriendRequestModel` (to receiver only - silent) |
| `friendRequestsList` | `FriendRequestModel[]` (pending requests for current user) |
| `pendingRequestsCount` | `{count: int}` (for badge updates) |
| `friendsList` | `UserModel[]` (all accepted friends) |
| `unfriended` | `{userId: int}` (notifies which user unfriended) |

**Connection**: Socket.IO with JWT token via query param `?token=xxx`. Server tracks online users via `Map<userId, socketId>`.

**Authorization**: Before `sendMessage` or `startConversation`, backend checks `areFriends(sender, recipient)`. If false, emits error: "You must be friends to send messages".

### Backend Limitations (no endpoints for these)
- No user search/discovery — must know exact email to send friend request
- No user profiles beyond basic info — users have `id`, `email`, `username`, `password`, `createdAt`
- No typing indicators, read receipts, or message editing/deletion
- No pagination — `getMessages` always returns last 50
- No last message included in `conversationsList` — must track client-side
- `conversations` table has no unique constraint on user pair in DB, deduplication done in `findOrCreate` service method
- Friend requests have no unique constraint on (sender, receiver) — intentional, allows resend after rejection

## Quick Reference (Find Stuff Fast)

### I want to modify friend request logic
→ `backend/src/friends/friends.service.ts` (9 methods: sendRequest, accept, reject, areFriends, etc.)
→ `backend/src/chat/chat.gateway.ts` (6 handlers: sendFriendRequest, acceptFriendRequest, etc.)

### I want to add a new WebSocket event for friends
→ Add handler in `backend/src/chat/chat.gateway.ts` (use @SubscribeMessage decorator)
→ Add listener in `frontend/lib/services/socket_service.dart` (socket.on() in connect())
→ Add callback in `frontend/lib/providers/chat_provider.dart` (pass to socketService.connect())

### I want to change the badge appearance
→ `frontend/lib/screens/conversations_screen.dart` (search "Stack" for badge UI in both layouts)

### I want to modify friend request UI
→ `frontend/lib/screens/friend_requests_screen.dart` (entire screen for accept/reject)
→ `frontend/lib/widgets/` (add custom widgets if needed)

### I want to add database column to FriendRequest
→ Edit `backend/src/friends/friend-request.entity.ts` (TypeORM will auto-migrate if synchronize: true)
→ Add corresponding field to `FriendRequestModel` in `frontend/lib/models/friend_request_model.dart`

### I want to debug friend authorization
→ Add logs in `backend/src/chat/chat.gateway.ts` before `areFriends()` call
→ Check `backend/src/friends/friends.service.ts` for areFriends() logic

### I want to test unfriend flow
→ Call `unfriend(userId)` from ChatProvider → triggers ChatGateway.handleUnfriend()
→ Checks: deletion of FriendRequest + deletion of Conversation + deletion of Messages (cascade)
→ Both users get `unfriended` event + `conversationsList` refreshed

## Entity Models (Backend)

```
User: id (PK), email (unique), username (unique), password (bcrypt), createdAt

Conversation: id (PK), userOne (FK→User, eager), userTwo (FK→User, eager), createdAt

Message: id (PK), content (text), sender (FK→User, eager), conversation (FK→Conversation, lazy), createdAt

FriendRequest (NEW):
  id (PK)
  sender (FK→User, eager, CASCADE DELETE)
  receiver (FK→User, eager, CASCADE DELETE)
  status (enum: PENDING, ACCEPTED, REJECTED) — default PENDING
  createdAt (auto timestamp)
  respondedAt (nullable, set on accept/reject)
  Index: (sender_id, receiver_id) — no unique constraint, allows resend after rejection
```

## Friend Requests System (New Feature)

### How It Works
1. **Send Request**: User A sends friend request to User B by email. If both have pending requests to each other → auto-accept both (improves UX).
2. **Accept/Reject**: User B accepts or rejects. Rejection is silent (sender not notified). No unique constraint on requests → resend allowed after rejection.
3. **Message Authorization**: `sendMessage` and `startConversation` check `areFriends()` before proceeding. Non-friends get error.
4. **Unfriend**: Deletes all accepted FriendRequests between users AND deletes the conversation (cascade delete messages). Both users notified via `unfriended` event.

### Backend Services
- **FriendsService** (backend/src/friends/friends.service.ts):
  - `sendRequest(sender, receiver)` → creates pending or auto-accepts mutual
  - `acceptRequest(requestId, userId)` → updates status to ACCEPTED
  - `rejectRequest(requestId, userId)` → updates status to REJECTED
  - `areFriends(userId1, userId2)` → boolean (for auth checks)
  - `getPendingRequests(userId)` → array of pending requests
  - `getFriends(userId)` → array of accepted friends
  - `getPendingRequestCount(userId)` → int (for badge)
  - `unfriend(userId1, userId2)` → deletes relationship + conversation

- **ChatGateway** (backend/src/chat/chat.gateway.ts):
  - Injects FriendsService
  - Calls `areFriends()` in `handleMessage()` and `handleStartConversation()`
  - Implements 6 new WebSocket handlers for friend requests

### Frontend Components
- **FriendRequestModel** (frontend/lib/models/friend_request_model.dart): Model with fromJson.
- **FriendRequestsScreen** (frontend/lib/screens/friend_requests_screen.dart): Full screen with accept/reject buttons, avatar circles, empty state.
- **ChatProvider** (frontend/lib/providers/chat_provider.dart):
  - `List<FriendRequestModel> _friendRequests`
  - `int _pendingRequestsCount`
  - `List<UserModel> _friends`
  - Methods: `sendFriendRequest()`, `acceptFriendRequest()`, `rejectFriendRequest()`, `fetchFriendRequests()`, `fetchFriends()`, `unfriend()`, `isFriend()`
  - Listens to 8 new WebSocket events
- **ConversationsScreen**: Red badge with pending count (mobile & desktop). Navigates to FriendRequestsScreen.
- **NewChatScreen**: Changed from "Start Chat" to "Send Friend Request" flow.
- **ChatDetailScreen**: Added unfriend PopupMenu button with confirmation dialog.

### Key Design Decisions
- **Auto-accept mutual**: If both users send requests simultaneously, both auto-accept → no conflict
- **No resend block**: No unique constraint on (sender, receiver), allows resend after rejection
- **Silent rejection**: Sender not notified when rejected (cleaner UX than spam)
- **Cascade delete**: Unfriend deletes conversation + all messages
- **Real-time badge**: `pendingRequestsCount` event updates badge immediately
- **Offline handling**: Pending count shown on reconnect

### Edge Cases Handled
- ✓ Duplicate pending request → ConflictException
- ✓ Self-request → ConflictException
- ✓ Unfriend while chatting → Chat closes, conversation removed from list
- ✓ Message to unfriended user → Blocked with error
- ✓ Accept after conversation created → Conversation already exists, accept still works

## Frontend Architecture Notes

### State Management
- **Provider** (ChangeNotifier) pattern. Two providers: `AuthProvider` + `ChatProvider`.
- `AuthProvider` handles JWT lifecycle: login → decode JWT (`sub`=userId, `email`) → save to SharedPreferences → auto-restore on app start (checks expiry via JwtDecoder).
- `ChatProvider` handles WebSocket: connect with token → listen to all events → manage conversations/messages state. The `openConversation()` method clears messages and fetches history.

### Navigation Flow
```
main.dart → AuthGate (watches AuthProvider.isLoggedIn)
  → false: AuthScreen (login/register)
  → true: ConversationsScreen (main hub)
    → Mobile: Navigator.push → ChatDetailScreen
    → Desktop (≥600px): side-by-side layout (list + embedded chat)
```

### Responsive Design
- Breakpoint at **600px width** — below = mobile (push navigation), above = desktop (master-detail)
- Use `LayoutBuilder` in `ConversationsScreen` to switch layouts
- All screens use `SafeArea` for phone notches/gesture bars

### Theme System (`rpg_theme.dart`)
- RPG color palette: background `#0A0A2E`, gold `#FFCC00`, purple `#7B7BF5`, border `#4A4AE0`, etc.
- `RpgTheme.themeData` — full `ThemeData` for MaterialApp
- `pressStart2P()` — retro font, use ONLY for titles/headers/logos
- `bodyFont()` — readable `Inter` font for body text, messages, form fields
- Rounded corners (8px for inputs, 16px for message bubbles)

### Key Patterns
- Conversation recipient is determined by comparing `conv.userOne.id` vs `currentUserId` — the other one is the recipient
- `startConversation(email)` is async via WebSocket — the response comes back as `openConversation` event, not a return value. Use `pendingOpenConversationId` in ChatProvider for navigation
- `sendFriendRequest(email)` is async via WebSocket — response comes as `friendRequestSent` event. Success shown via SnackBar, then pop screen.
- Message bubbles: sent = right-aligned + gold accent, received = left-aligned + purple accent
- Last messages per conversation tracked client-side in `Map<int, MessageModel>` since backend doesn't include them in conversations list
- **IMPORTANT: Friend request check happens BEFORE conversation create** — `areFriends()` is called in ChatGateway.handleMessage() before findOrCreate()
- Badge count is reactive — ChatProvider notifies listeners on `pendingRequestsCount` event
- ConversationsScreen rebuilds when badge count changes via `Consumer<ChatProvider>`

### Dependencies (pubspec.yaml)
- `provider ^6.1.2` — state management
- `socket_io_client ^2.0.3+1` — WebSocket (Socket.IO)
- `http ^1.2.2` — REST calls
- `jwt_decoder ^2.0.1` — JWT parsing
- `shared_preferences ^2.3.4` — token persistence
- `google_fonts ^6.2.1` — Press Start 2P + Inter fonts

### Gotchas
- Socket.IO events return `dynamic` data — always cast to `Map<String, dynamic>` or `List<dynamic>` before parsing
- `AppConfig.baseUrl` falls back to `Uri.base.origin` on web builds — important for Docker/nginx deployment
- The `onOpenConversation` event fires inside ChatProvider (not in widget tree) — cannot call `Navigator.push` directly from provider. Use a reactive pattern (e.g., `pendingOpenConversationId` watched by the screen)
- When deleting old widget files, make sure no imports reference them — check `auth_form.dart`, `auth_screen.dart`, `main.dart`
- `flutter analyze` should pass with zero issues before committing
- Platform is Windows — use `cd frontend &&` prefix for all Flutter commands

**Friend Requests System Gotchas:**
- `FriendsService.areFriends()` is called in ChatGateway BEFORE creating conversation — failure blocks message entirely
- `friendRequestRejected` event sent ONLY to receiver (silent rejection) — sender gets no notification
- No unique constraint on (sender_id, receiver_id) in friend_requests table — intentional, allows resend after rejection
- Mutual requests auto-accept both directions in `sendRequest()` — check for existing reverse pending before creating new request
- `unfriend()` deletes ONLY accepted FriendRequests, not pending or rejected ones
- `ConversationsService.findByUsers()` is case-sensitive on email lookups (inherited from database)
- Badge count fetched on connect and updated per `pendingRequestsCount` event — ensure ChatProvider.connect() calls `fetchFriendRequests()`
- FriendRequestsScreen emits `getFriendRequests` in initState — be aware of double-emits if screen is revisited
