# Fireplace

Fireplace – real-time messenger with RPG-themed UI. NestJS backend with WebSocket (Socket.IO), Flutter frontend, JWT authentication, and PostgreSQL. Run everything with Docker Compose.

---

## Tech Stack

| Layer          | Technology                   |
|----------------|------------------------------|
| Backend        | NestJS (Node.js / TypeScript)|
| Frontend       | Flutter (Dart)               |
| Database       | PostgreSQL 16                |
| WebSocket      | Socket.IO                    |
| Authentication | JWT + Passport + bcrypt      |
| ORM            | TypeORM                      |
| Containers     | Docker + Docker Compose      |

---

## Quick Start (Mobile Development)

> Requirements: [Flutter SDK](https://flutter.dev/docs/get-started/install), [Docker](https://docs.docker.com/get-docker/)

```bash
# 1. Clone the repository
git clone https://github.com/Lentach/fireplace.git
cd fireplace

# 2. Start backend + database
docker-compose up

# 3. In another terminal: Run Flutter on your device
cd frontend
flutter devices              # List available devices
flutter run -d <device-id>   # Hot-reload enabled
```

- **Backend API:** http://192.168.1.11:3000 (accessible from phone)
- **Frontend:** Native Flutter app with instant hot-reload

**Optional - Web Preview:**
```bash
docker-compose -f docker-compose.web.yml up --build
```
- **Frontend (web):** http://localhost:8080

---

## Running Locally (without Docker)

> Requirements: Node.js 20+, PostgreSQL, Flutter SDK

### Backend

```bash
cd backend

# 1. Install dependencies
npm install

# 2. Set environment variables (optional — defaults are provided)
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=postgres
export DB_PASS=postgres
export DB_NAME=chatdb
export JWT_SECRET=my-secret-key

# 3. Run in development mode (hot-reload)
npm run start:dev
```

### Frontend

**Mobile (Recommended):**
```bash
cd frontend

# 1. Install dependencies
flutter pub get

# 2. Connect device via USB or WiFi
flutter devices

# 3. Run on device
flutter run -d <device-id> --dart-define=BASE_URL=http://192.168.1.11:3000
```

**Web (Optional):**
```bash
cd frontend
flutter run -d chrome --dart-define=BASE_URL=http://localhost:3000
```

---

## Project Structure

```
fireplace/
├── backend/
│   ├── src/
│   │   ├── auth/                # Registration, login, JWT strategy
│   │   ├── users/               # User entity, service
│   │   ├── conversations/       # Conversation entity (1-on-1), findOrCreate
│   │   ├── messages/            # Message entity, CRUD
│   │   ├── chat/                # WebSocket Gateway (Socket.IO)
│   │   ├── app.module.ts        # Root module
│   │   └── main.ts              # Entry point
│   ├── Dockerfile
│   └── package.json
├── frontend/
│   ├── lib/
│   │   ├── config/              # App configuration (base URL)
│   │   ├── models/              # Data models (User, Conversation, Message)
│   │   ├── services/            # API and Socket.IO services
│   │   ├── providers/           # State management (Auth, Chat)
│   │   ├── screens/             # Auth and Chat screens
│   │   ├── widgets/             # Reusable RPG-themed widgets
│   │   ├── theme/               # RPG theme constants
│   │   └── main.dart            # App entry point
│   ├── Dockerfile
│   └── nginx.conf
├── docker-compose.yml
└── README.md
```

---

## API Endpoints

### Register

```
POST /auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "secret123"
}
```

### Login

```
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "secret123"
}
```

The response returns an `access_token` (JWT) which you use to connect via WebSocket.

---

## WebSocket

Connect via Socket.IO with a JWT token:

```js
const socket = io('http://localhost:3000', {
  query: { token: 'YOUR_JWT_TOKEN' }
});
```

### Events

| Event (client emits)    | Payload                                | Description                       |
|-------------------------|----------------------------------------|-----------------------------------|
| `sendMessage`           | `{ recipientId, content }`             | Send a message                    |
| `startConversation`     | `{ recipientEmail }`                   | Start a conversation by email     |
| `getMessages`           | `{ conversationId }`                   | Get message history               |
| `getConversations`      | *(none)*                               | Get conversation list             |

| Event (server emits)    | Description                            |
|-------------------------|----------------------------------------|
| `messageSent`           | Confirmation that message was sent     |
| `newMessage`            | New message from another user          |
| `messageHistory`        | Message history for a conversation     |
| `conversationsList`     | User's conversation list               |
| `openConversation`      | Automatically open a new conversation  |

---

## Environment Variables

| Variable     | Default           | Description             |
|--------------|-------------------|-------------------------|
| `DB_HOST`    | `localhost`       | PostgreSQL host         |
| `DB_PORT`    | `5432`            | Database port           |
| `DB_USER`    | `postgres`        | Database user           |
| `DB_PASS`    | `postgres`        | Database password       |
| `DB_NAME`    | `chatdb`          | Database name           |
| `JWT_SECRET` | *(in code)*       | JWT signing key         |
| `PORT`       | `3000`            | Application port        |

---

## npm Scripts (backend)

```bash
cd backend
npm run build          # Compile TypeScript
npm run start:dev      # Development mode (hot-reload)
npm run start          # Run compiled version
npm run lint           # Linting (ESLint)
npm run test           # Unit tests
npm run test:e2e       # End-to-end tests
```

---

## License

UNLICENSED — private project.
