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
- `screens/auth_screen.dart` — Login/register RPG-themed UI.
- `screens/chat_screen.dart` — Chat with sidebar, messages, RPG theme.
- `theme/rpg_theme.dart` — All colors, text styles, decorations (retro RPG look).

**Data flow for sending a message:**
Client connects via WebSocket with JWT token → emits `sendMessage` with `{recipientId, content}` → Gateway finds/creates conversation → saves message to PostgreSQL → emits `newMessage` to recipient socket (if online) + `messageSent` confirmation to sender.

**WebSocket events:** `sendMessage`, `getMessages`, `getConversations`, `newMessage`, `messageSent`, `messageHistory`, `conversationsList`.

## Database

PostgreSQL with TypeORM. `synchronize: true` auto-creates tables (dev only).
Three tables: `users`, `conversations` (user_one_id, user_two_id), `messages` (sender_id, conversation_id, content).

## Environment variables

`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME`, `JWT_SECRET`, `PORT` — all have defaults for local dev.

Frontend uses `BASE_URL` dart define (defaults to `http://localhost:3000`). In Docker, nginx proxies API/WebSocket requests to the backend.
