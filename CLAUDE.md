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
- `UsersModule` — User entity and service. Shared dependency for Auth and Chat.
- `ConversationsModule` — Conversation entity linking two users. findOrCreate pattern prevents duplicates.
- `MessagesModule` — Message entity with content, sender, conversation FK.
- `ChatModule` — WebSocket Gateway (Socket.IO). Handles real-time messaging. Verifies JWT on connection via query param `?token=`.

**Frontend — Flutter app** with Provider state management:

- `providers/auth_provider.dart` — JWT token, login/register/logout, persists token via SharedPreferences.
- `providers/chat_provider.dart` — conversations list, messages, active conversation, socket events.
- `services/api_service.dart` — REST calls to /auth/register, /auth/login.
- `services/socket_service.dart` — Socket.IO wrapper for real-time events.
- `screens/auth_screen.dart` — Login/register UI with RPG title, modern Material form.
- `screens/conversations_screen.dart` — Main hub: conversation list (mobile) or master-detail (desktop ≥600px).
- `screens/chat_detail_screen.dart` — Full chat view with messages and input bar. Used standalone (mobile) or embedded (desktop).
- `screens/new_chat_screen.dart` — Start a new conversation by entering an email.
- `theme/rpg_theme.dart` — Colors, ThemeData, `pressStart2P()` for titles, `bodyFont()` (Inter) for body text.

**Data flow for sending a message:**
Client connects via WebSocket with JWT token → emits `sendMessage` with `{recipientId, content}` → Gateway finds/creates conversation → saves message to PostgreSQL → emits `newMessage` to recipient socket (if online) + `messageSent` confirmation to sender.

**WebSocket events:** `sendMessage`, `getMessages`, `getConversations`, `newMessage`, `messageSent`, `messageHistory`, `conversationsList`.

## Database

PostgreSQL with TypeORM. `synchronize: true` auto-creates tables (dev only).
Three tables: `users`, `conversations` (user_one_id, user_two_id), `messages` (sender_id, conversation_id, content).

## Environment variables

`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME`, `JWT_SECRET`, `PORT` — all have defaults for local dev.

Frontend uses `BASE_URL` dart define (defaults to `http://localhost:3000`). In Docker, nginx proxies API/WebSocket requests to the backend.

## Backend API Reference

### REST Endpoints (only 2 exist)
- `POST /auth/register` — Body: `{email, password}` → Returns `{id, email}`. Password min 6 chars. ConflictException if email exists.
- `POST /auth/login` — Body: `{email, password}` → Returns `{access_token}`. UnauthorizedException on bad creds.

**There are NO other REST endpoints.** All chat operations use WebSocket.

### WebSocket Events

| Client → Server | Payload | Response Event |
|-----------------|---------|----------------|
| `sendMessage` | `{recipientId: int, content: string}` | `messageSent` to sender, `newMessage` to recipient |
| `startConversation` | `{recipientEmail: string}` | `conversationsList` + `openConversation` to sender |
| `getMessages` | `{conversationId: int}` | `messageHistory` (last 50 messages, oldest first) |
| `getConversations` | (no payload) | `conversationsList` |

| Server → Client | Payload |
|-----------------|---------|
| `conversationsList` | `ConversationModel[]` |
| `messageHistory` | `MessageModel[]` |
| `messageSent` | `MessageModel` (confirmation) |
| `newMessage` | `MessageModel` (incoming from other user) |
| `openConversation` | `{conversationId: int}` |
| `error` | `{message: string}` |

**Connection**: Socket.IO with JWT token via query param `?token=xxx`. Server tracks online users via `Map<userId, socketId>`.

### Backend Limitations (no endpoints for these)
- No user search/discovery — must know exact email to start conversation
- No contacts/friends list — conversations list is the only "contacts"
- No user profiles — users only have `id`, `email`, `password`, `createdAt`
- No typing indicators, read receipts, or message editing/deletion
- No pagination — `getMessages` always returns last 50
- No last message included in `conversationsList` — must track client-side
- `conversations` table has no unique constraint on user pair in DB, deduplication done in `findOrCreate` service method

## Entity Models (Backend)

```
User: id (PK), email (unique), password (bcrypt), createdAt
Conversation: id (PK), userOne (FK→User, eager), userTwo (FK→User, eager), createdAt
Message: id (PK), content (text), sender (FK→User, eager), conversation (FK→Conversation, lazy), createdAt
```

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
- Message bubbles: sent = right-aligned + gold accent, received = left-aligned + purple accent
- Last messages per conversation tracked client-side in `Map<int, MessageModel>` since backend doesn't include them in conversations list

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
