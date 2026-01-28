# MVP Chat App

Real-time 1-on-1 chat application. NestJS backend with WebSocket communication (Socket.IO), JWT authentication, and PostgreSQL database. Run everything with a single command using Docker Compose.

---

## Tech Stack

| Layer          | Technology                   |
|----------------|------------------------------|
| Backend        | NestJS (Node.js / TypeScript)|
| Database       | PostgreSQL 16                |
| WebSocket      | Socket.IO                    |
| Authentication | JWT + Passport + bcrypt      |
| ORM            | TypeORM                      |
| Containers     | Docker + Docker Compose      |

---

## Quick Start (Docker)

> Requirements: [Docker](https://docs.docker.com/get-docker/) and Docker Compose

```bash
# 1. Clone the repository
git clone https://github.com/Lentach/mvp-chat-app.git
cd mvp-chat-app

# 2. Build and run
docker-compose up --build
```

The app will be available at **http://localhost:3000**

A built-in test client (frontend) is served at the same address and opens automatically in the browser.

---

## Running Locally (without Docker)

> Requirements: Node.js 20+, PostgreSQL

```bash
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

## Architecture

```
src/
├── auth/                # Registration, login, JWT strategy
├── users/               # User entity, service
├── conversations/       # Conversation entity (1-on-1), findOrCreate
├── messages/            # Message entity, CRUD
├── chat/                # WebSocket Gateway (Socket.IO)
├── public/              # Built-in test client (HTML)
├── app.module.ts        # Root module
└── main.ts              # Entry point
```

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

## npm Scripts

```bash
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
