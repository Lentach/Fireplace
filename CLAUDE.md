# CLAUDE.md — MVP Chat App

**Last updated:** 2026-02-12

**Rule:** Update this file after every code change. Single source of truth for agents. **A future agent must be able to read ONLY this file and understand the current state of the project without reading every source file.**

**Session rule:** Read `.cursor/session-summaries/LATEST.md` at start; write `YYYY-MM-DD-session.md` and update `LATEST.md` at end. `.cursor/rules/session-summaries.mdc`

**Code rule:** All code in English (vars, functions, comments, commits). If you find Polish in code files (.dart, .ts, .js, etc.), refactor to English. Documentation (.md) can be in Polish. `.cursor/rules/code-in-english.mdc`

---

## 1. Critical — Read First

| Rule | Why |
|------|-----|
| **TypeORM relations** | Always `relations: ['sender','receiver']` on friendRequestRepository. Without: empty objects, crashes. |
| **TypeORM .delete()** | Cannot use nested relation conditions. Use find-then-remove: `.find()` then `.remove()`. |
| **Socket.IO (Dart)** | Use `enableForceNew()` when reconnecting with new JWT (logout→login). Caches by URL otherwise. |
| **Provider→Navigator** | `ChatProvider` can't call `Navigator.push`. Use `consumePendingOpen()`: set ID, notifyListeners, screen pops in build. |
| **Multiple backends** | If frontend shows weird data vs backend logs: kill local `node.exe`, use Docker only. |
| **TypeORM timestamp comparison** | `expiresAt` may be string or Date from pg driver. Always use `new Date(val).getTime()` for comparisons, never `val > new Date()`. |

---

## 2. Quick Start

**Stack:** NestJS + Flutter + PostgreSQL + Socket.IO + JWT. Mobile-first, web optional.

**Structure:** `backend/` :3000, `frontend/` Flutter app (run locally or build for web :8080). Manual E2E scripts in `scripts/` (see `scripts/README.md`).

**Development workflow:**

1. **Start backend + DB** (always):
   ```bash
   docker-compose up
   ```
   Backend: http://192.168.1.11:3000 (accessible from phone)

2. **Run Flutter on device** (mobile dev - recommended):
   ```bash
   cd frontend
   flutter devices  # List available devices
   flutter run -d <device-id>  # Hot-reload enabled
   ```

3. **Or run web build** (optional, for web testing):
   ```bash
   docker-compose -f docker-compose.web.yml up --build
   ```
   Frontend: http://192.168.1.11:8080

**Before run:**
- Kill existing node processes: `taskkill //F //IM node.exe`
- Ensure phone/computer on same WiFi network
- Update `BASE_URL` in flutter run: `--dart-define=BASE_URL=http://192.168.1.11:3000`

**Frontend config:** `BASE_URL` via dart-define or hardcoded default. JWT stored in SharedPreferences (`jwt_token`).

---

## 3. Architecture Diagrams

### 3.1 System overview

```mermaid
flowchart TB
  subgraph client [Flutter App]
    AuthGate
    AuthScreen
    MainShell
    AuthGate --> |logged out| AuthScreen
    AuthGate --> |logged in| MainShell
  end

  subgraph main_shell [MainShell - BottomNav]
    Tab0[Tab 0: Conversations]
    Tab1[Tab 1: Archive]
    Tab2[Tab 2: Settings]
    Tab0 --> ConversationsScreen
    Tab1 --> ArchivePlaceholderScreen
    Tab2 --> SettingsScreen
  end

  subgraph conv_tab [Conversations tab]
    ConvHeader[Header: avatar+shield, Conversations, plus]
    ConvList[Conversation list with Divider]
    PlusTap[Plus tap]
    AddScreen[AddOrInvitationsScreen]
    ConvHeader --> ConvList
    ConvHeader --> PlusTap
    PlusTap --> AddScreen
  end

  subgraph add_screen [AddOrInvitationsScreen]
    TabAdd[Tab: Add by email]
    TabInv[Tab: Friend requests]
  end

  subgraph backend [NestJS Backend]
    REST[REST: /auth, /users]
    WS[WebSocket Gateway]
    DB[(PostgreSQL)]
    REST --> DB
    WS --> DB
  end

  client --> |REST + JWT| REST
  client --> |Socket.IO ?token=JWT| WS
```

### 3.2 Post-login navigation flow

```mermaid
flowchart LR
  AuthGate --> |isLoggedIn| MainShell
  MainShell --> |index 0| ConversationsScreen
  MainShell --> |index 1| ArchivePlaceholderScreen
  MainShell --> |index 2| SettingsScreen

  ConversationsScreen --> |plus| AddOrInvitationsScreen
  AddOrInvitationsScreen --> |pop conversationId| ConversationsScreen

  ConversationsScreen --> |tap conversation / mobile| ChatDetailScreen
  ConversationsScreen --> |desktop| ChatDetailScreen embedded

  SettingsScreen --> |Logout| AuthGate
```

- **Mobile:** Bottom nav always visible. Conversations tab = custom header + list. Plus → AddOrInvitationsScreen (push). Tap conversation → push ChatDetailScreen.
- **Desktop:** Same MainShell; ConversationsScreen shows sidebar (header + list) + embedded ChatDetailScreen in right pane. Breakpoint: `AppConstants.layoutBreakpointDesktop` (600px).

### 3.3 Auth flow

```mermaid
sequenceDiagram
  participant U as User
  participant AuthScreen
  participant AuthProvider
  participant Api
  participant Backend
  participant MainShell

  U->>AuthScreen: email + password
  AuthScreen->>AuthProvider: login(email, password)
  AuthProvider->>Api: POST /auth/login
  Api->>Backend: login
  Backend-->>Api: JWT + user payload
  Api-->>AuthProvider: accessToken
  AuthProvider->>AuthProvider: decode JWT, set currentUser, save token (SharedPreferences)
  AuthProvider->>AuthProvider: notifyListeners()
  AuthGate->>AuthGate: build: auth.isLoggedIn == true
  AuthGate->>MainShell: return MainShell()
  Note over MainShell: ConversationsScreen initState: ChatProvider.connect(token, userId)
```

**Logout:** User taps Logout in Settings tab → `chat.disconnect()`, `auth.logout()` (clear token + currentUser, notifyListeners). AuthGate rebuilds → `auth.isLoggedIn == false` → return AuthScreen. On logout transition AuthGate also calls `chat.disconnect()` in addPostFrameCallback.

---

## 4. Database Schema

**PostgreSQL, TypeORM `synchronize: true`.**

```mermaid
erDiagram
  users ||--o{ conversations : "user_one"
  users ||--o{ conversations : "user_two"
  users ||--o{ messages : "sender"
  users ||--o{ friend_requests : "sender"
  users ||--o{ friend_requests : "receiver"
  conversations ||--o{ messages : "conversation"

  users {
    int id PK
    string email
    string username
    string password
    string profilePictureUrl
    string profilePicturePublicId
  }

  conversations {
    int id PK
    int user_one_id FK
    int user_two_id FK
  }

  messages {
    int id PK
    text content
    int sender_id FK
    int conversation_id FK
    timestamp createdAt
  }

  friend_requests {
    int id PK
    int sender_id FK
    int receiver_id FK
    enum status "PENDING, ACCEPTED, REJECTED"
  }
```

- **users:** No cascade. Delete account must manually delete dependents (see §8 Backend mechanisms).
- **conversations:** user_one_id, user_two_id → users(id).
- **messages:** conversation_id → conversations(id), sender_id → users(id). Delete conversation: delete messages first, then conversation.
- **friend_requests:** sender_id, receiver_id → users(id). For delete/unfriend use **find-then-remove** (no .delete() with relation conditions).

---

## 5. WebSocket Event Map

**Connection:** Client connects with `?token=JWT` (query or auth). Gateway verifies JWT, loads user, sets `client.data.user = { id, email, username }`. No token or invalid user → disconnect.

**All events below: client emits to server; server may emit back to client and/or to other socket(s).**

| Client emit | Server handler | Server emit (to caller) | Server emit (to others) |
|-------------|----------------|--------------------------|--------------------------|
| **sendMessage** | ChatMessageService.handleSendMessage | `messageSent` (message payload) | To recipient: `newMessage` (same payload) |
| **getMessages** | ChatMessageService.handleGetMessages | `messageHistory` (array of messages) | — |
| **startConversation** | ChatConversationService.handleStartConversation | `conversationsList`, `openConversation` { conversationId } | — |
| **getConversations** | ChatConversationService.handleGetConversations | `conversationsList` (array) | — |
| **startConversation** | ChatConversationService.handleStartConversation | `conversationsList`, `openConversation` { conversationId } | — |
| **deleteConversation** | ChatConversationService.handleDeleteConversation | `conversationsList`, `unfriended` { userId } | To other user: `unfriended` { userId }; then both get new `conversationsList` |
| **sendFriendRequest** | ChatFriendRequestService.handleSendFriendRequest | If pending: `friendRequestSent` (payload). If auto-accept: `friendRequestAccepted`, `friendsList`, `conversationsList`, `openConversation` { conversationId }, `pendingRequestsCount` { count } | To recipient if pending: `newFriendRequest`, `pendingRequestsCount`. If auto-accept: recipient gets `friendRequestAccepted`, `friendsList`, `conversationsList`, `openConversation`, `pendingRequestsCount` |
| **acceptFriendRequest** | ChatFriendRequestService.handleAcceptFriendRequest | `friendRequestAccepted`, `friendsList`, `conversationsList`, `openConversation` { conversationId }, `pendingRequestsCount` | To sender: `friendRequestAccepted`, `friendsList`, `conversationsList`, `openConversation`, `pendingRequestsCount` |
| **rejectFriendRequest** | ChatFriendRequestService.handleRejectFriendRequest | `friendRequestRejected`, `friendRequestsList`, `pendingRequestsCount` | — |
| **getFriendRequests** | ChatFriendRequestService.handleGetFriendRequests | `friendRequestsList` (array) | — |
| **getFriends** | ChatFriendRequestService.handleGetFriends | `friendsList` (array of users) | — |
| **unfriend** | ChatFriendRequestService.handleUnfriend | `unfriended`, `conversationsList` | To other: `unfriended` { userId }, `conversationsList` |
| **messageDelivered** | ChatMessageService.handleMessageDelivered | — | To sender: `messageDelivered` { messageId, deliveryStatus: 'DELIVERED' } |
| **markConversationRead** | ChatMessageService.handleMarkConversationRead | — | To each sender of marked messages: `messageDelivered` { messageId, deliveryStatus: 'READ' } |

**Payload shapes (essential):**

- **messageSent / newMessage:** `{ id, content, senderId, senderEmail, senderUsername, conversationId, createdAt }`
- **conversationsList:** array of `{ id, userOne, userTwo }` (user objects with id, email, username, profilePictureUrl).
- **openConversation:** `{ conversationId: number }`
- **error:** `{ message: string }`
- **pendingRequestsCount:** `{ count: number }`
- **friendRequestAccepted / newFriendRequest / friendRequestSent:** FriendRequest payload (id, sender, receiver, status).
- **unfriended:** `{ userId: number }` (the peer that was unfriended).

**Client DTOs (backend validates):** SendMessageDto: recipientId, content. SendFriendRequestDto / StartConversationDto: recipientEmail. AcceptFriendRequestDto / RejectFriendRequestDto: requestId. DeleteConversationDto: conversationId. GetMessagesDto: conversationId, optional limit/offset. UnfriendDto: userId. messageDelivered: messageId. markConversationRead: conversationId.

---

## 6. REST API

| Method | Path | Auth | Body / purpose |
|--------|------|------|----------------|
| POST | /auth/register | — | email, password, username? → 201 |
| POST | /auth/login | — | email, password → { accessToken } + JWT payload (sub, email, username, profilePictureUrl) |
| POST | /users/profile-picture | JWT | multipart file (JPEG/PNG, max 5MB) → update profilePictureUrl, profilePicturePublicId |
| POST | /users/reset-password | JWT | oldPassword, newPassword |
| DELETE | /users/account | JWT | body: { password } → deletes user and all dependents |

**Password rules:** 8+ chars, at least one uppercase, one lowercase, one number.

**Rate limits:** login 5/15min, register 3/h, upload 10/h.

---

## 7. Frontend Mechanisms (Detail)

### 7.1 AuthGate and logout

- **AuthGate** (main.dart): Watches AuthProvider. If `auth.isLoggedIn` → MainShell; else AuthScreen.
- **Logout transition:** When `isLoggedIn` goes true→false, in addPostFrameCallback AuthGate calls `chat.disconnect()` so socket is cleaned up.
- **SettingsScreen Logout:** Calls `chat.disconnect()`, `auth.logout()`. Then `Navigator.pop(context)` only if `Navigator.of(context).canPop()` (so when used as tab in MainShell it does not pop).

### 7.2 ChatProvider.connect and reconnect

- **connect(token, userId):** Cancels any reconnect timer, sets _intentionalDisconnect = false, _tokenForReconnect = token. **Clears all state** (conversations, messages, activeConversationId, lastMessages, pendingOpenConversationId, friendRequests, pendingRequestsCount, friends, errorMessage). notifyListeners(). Disposes old socket if any, then creates new SocketService with **enableForceNew()** and connects. On connect: getConversations(), then notifyListeners().
- **disconnect():** Sets _intentionalDisconnect = true, cancels reconnect timer, then socket.disconnect/dispose/null. No notifyListeners() in disconnect (AuthGate will rebuild anyway).
- **onDisconnect:** If not _intentionalDisconnect and _tokenForReconnect != null, starts reconnect with exponential backoff (max 5 attempts). Reconnect calls connect(_tokenForReconnect, currentUserId).

### 7.3 consumePendingOpen (Provider→Navigator)

- **Problem:** ChatProvider cannot call Navigator.push (no BuildContext).
- **Mechanism:** Backend emits `openConversation` { conversationId }. ChatProvider sets _pendingOpenConversationId = id, notifyListeners(). Screen that is on top of the stack (e.g. AddOrInvitationsScreen or FriendRequestsScreen) in its build() calls `chat.consumePendingOpen()` → returns id and clears it. If id != null, screen does addPostFrameCallback → Navigator.pop(context, id). Caller (ConversationsScreen or AddOrInvitationsScreen) gets result and calls _openChat(id): openConversation(id), then on mobile pushes ChatDetailScreen(conversationId).
- **Where used:** AddOrInvitationsScreen (both tabs), ConversationsScreen (when returning from AddOrInvitationsScreen with result).

### 7.4 consumeFriendRequestSent

- After sendFriendRequest, backend may emit `friendRequestSent`. ChatProvider sets _friendRequestJustSent = true. Add by email tab (or NewChatScreen) in build() calls `chat.consumeFriendRequestSent()`; if true, shows top snackbar and Navigator.pop(context). Used so the “Send Friend Request” flow can close the screen and show success.

### 7.7 Notifications (top snackbar)

- All transient notifications (errors, success, "coming soon") use **showTopSnackBar** from `widgets/top_snackbar.dart` so they appear **at the top** of the screen and do not cover the chat input bar at the bottom. Implemented via Overlay; optional `backgroundColor`; auto-dismiss after 2.5s.

### 7.5 Message handling

- **messageSent** (own send) and **newMessage** (incoming): both handled by same _handleIncomingMessage. Updates _lastMessages[conversationId], and if conversation is active adds to _messages, then notifyListeners().

### 7.6 Theme and layout

- **RpgTheme:** themeData (dark), themeDataLight. SettingsProvider.themeMode drives MaterialApp.themeMode. Breakpoint 600px: layoutBreakpointDesktop. Conversations list separator: Divider with convItemBorderDark / convItemBorderLight.

---

## 8. Backend Mechanisms (Detail)

### 8.1 Delete account cascade

- User entity has **no** TypeORM cascade. users.service deleteAccount(userId, password):
  1. Verify password.
  2. Delete Cloudinary avatar if profilePicturePublicId set.
  3. Find all conversations where user is userOne or userTwo. For each: delete messages (messageRepo.delete({ conversation })), then delete conversation.
  4. Find all friend_requests where sender or receiver is userId; **remove(records)** (find-then-remove).
  5. Remove user.

### 8.2 Avatar update (Cloudinary)

- Overwrite uses same public_id. So: only call cloudinary.deleteAvatar(oldPublicId) when **oldPublicId !== newPublicId**. users.service updateProfilePicture: if user.profilePicturePublicId && user.profilePicturePublicId !== publicId then deleteAvatar(old).

### 8.3 FriendRequest relations

- Every find/findOne on friendRequestRepository **must** use `relations: ['sender','receiver']`. Files: friends.service.ts (sendRequest, acceptRequest, rejectRequest, getPendingRequests, getFriends). Otherwise sender/receiver are undefined and UI/backend can crash.

### 8.4 Unfriend / delete friend_requests

- TypeORM .delete() does **not** support nested relation conditions. Use find with where [{ sender: { id: A }, receiver: { id: B } }, { sender: { id: B }, receiver: { id: A } }], then repo.remove(records).

### 8.5 deleteConversation

- chat-conversation.service handleDeleteConversation: must call **friendsService.unfriend(userId, otherUserId)** first (so friend_requests row is removed), then delete messages for conversation, then delete conversation. If unfriend is skipped, FK or logic can break.

### 8.6 Conversation/message delete

- messageRepo.delete({ conversation: { id } }) is valid (single relation). conversations.service uses this before deleting the conversation.

---

## 9. File Map (Where to Edit)

**Backend (NestJS):**

| Change | File(s) |
|--------|--------|
| Auth (register/login) | auth/auth.service.ts, auth.controller.ts, dto |
| User CRUD / profile picture / reset password / delete account | users/users.service.ts, users.controller.ts |
| Delete account cascade | users/users.service.ts (deleteAccount), users.module.ts (repos) |
| Friend request logic | friends/friends.service.ts (relations!), chat/services/chat-friend-request.service.ts |
| Conversation logic | conversations/conversations.service.ts, chat/services/chat-conversation.service.ts |
| Message logic | messages/messages.service.ts, chat/services/chat-message.service.ts |
| WebSocket events (new event) | chat/dto/chat.dto.ts, chat/services/*.ts, chat.gateway.ts |
| Avatar/Cloudinary | cloudinary/cloudinary.service.ts, users/users.controller.ts |

**Frontend (Flutter):**

| Change | File(s) |
|--------|--------|
| App root / auth gate | main.dart |
| Post-login shell / bottom nav | screens/main_shell.dart |
| Conversations list / header / plus | screens/conversations_screen.dart |
| Add by email + Friend requests tabs | screens/add_or_invitations_screen.dart |
| Archive placeholder | screens/archive_placeholder_screen.dart |
| Settings / logout | screens/settings_screen.dart |
| Chat thread UI | screens/chat_detail_screen.dart |
| Socket connection / events | services/socket_service.dart, providers/chat_provider.dart |
| Auth state / login / register | providers/auth_provider.dart, services/api_service.dart |
| Theme / colors | theme/rpg_theme.dart, providers/settings_provider.dart |
| Constants (breakpoint, page size, reconnect) | constants/app_constants.dart |
| Conversation tile / avatar | widgets/conversation_tile.dart, widgets/avatar_circle.dart |
| Top notifications (no bottom SnackBar) | widgets/top_snackbar.dart — use showTopSnackBar() |

---

## 10. Quick Reference — Find Code

| Task | Location |
|------|----------|
| Friend logic | friends/friends.service.ts + chat/services/chat-friend-request.service.ts |
| Message logic | messages/messages.service.ts + chat/services/chat-message.service.ts |
| Conversation logic | conversations/conversations.service.ts + chat/services/chat-conversation.service.ts |
| Gateway | chat/chat.gateway.ts |
| Add WebSocket event | dto → service handler → gateway @SubscribeMessage → socket_service.dart → chat_provider.dart |
| Add user REST endpoint | users.service → users.controller @UseGuards(JwtAuthGuard) → api_service → auth_provider / settings_screen |
| Add FriendRequest column | friend-request.entity.ts → friend_request_model.dart (TypeORM sync) |
| Settings UI | screens/settings_screen.dart, widgets/dialogs/ |
| Avatar/Cloudinary | cloudinary.service.ts, users.controller.ts, avatar_circle.dart |
| Theme | RpgTheme (themeData, themeDataLight), SettingsProvider |
| Constants | lib/constants/app_constants.dart |
| Auto-open after accept | openConversation → consumePendingOpen() → Navigator.pop(id) → _openChat(id) |
| Nav (post-login) | main.dart AuthGate → MainShell; Conversations tab: custom header, plus → AddOrInvitationsScreen; Settings: Logout |

---

## 11. Critical Gotchas (Summary)

- **TypeORM .delete() with relations:** Use find-then-remove for friend_requests (and any multi-relation condition). Single-relation delete is OK (e.g. messages by conversation).
- **deleteConversation:** Must call unfriend() before deleting conversation.
- **consumePendingOpen:** Set ID in provider, notifyListeners; screen in build() consumes and pops with result.
- **Socket.IO Dart:** enableForceNew() when reconnecting with new JWT.
- **Multiple backends:** Kill local node; use one backend only (Docker or local).

---

## 12. Chat Screen Redesign (2026-02-04)

Telegram/Wire-inspired UI with delivery indicators, disappearing messages, ping notifications, and action tiles.

### New Message Features

- **Delivery Status Tracking:** SENDING (clock), SENT (✓ grey), DELIVERED (✓ grey), READ (✓✓ blue) on own messages only. One check = delivered; two checks = read (recipient opened chat). Backend: `MessageDeliveryStatus` (SENDING, SENT, DELIVERED, READ). Client emits `messageDelivered`(messageId) when receiving; emits `markConversationRead`(conversationId) when opening/viewing chat so sender sees read receipts.
- **Disappearing Messages:** Global timer per conversation (30s, 1m, 5m, 1h, 1d, Off). Set via Timer action tile. Messages include `expiresAt` field. **Three-layer expiration:** (1) Frontend `removeExpiredMessages()` called every 1s by ChatDetailScreen timer — instant vanish at zero. (2) Backend cron deletes from DB every minute. (3) `handleGetMessages` + `onMessageHistory` both filter out expired messages.
- **Ping Messages:** One-shot notification with empty content and `messageType=PING`. Backend emits `pingSent` to sender, `newPing` to recipient. UI shows campaign icon + "PING!" text.
- **Message Types:** TEXT, PING, IMAGE, DRAWING (last two not fully implemented).

### UI Components

- **ChatMessageBubble:** Shows delivery icon (clock/✓/✓✓) + timer countdown if `expiresAt` set. Ping messages display with campaign icon.
- **ChatInputBar:** Arrow toggle for action panel, text field, mic/send toggle. Orange timer indicator bar above input when disappearing timer is active (shows "Disappearing messages: Xm"). Action panel slides open with ChatActionTiles.
- **ChatActionTiles:** Horizontal scroll row with 6 tiles: Timer (dialog with duration options), Ping (sends ping), Camera, Draw, GIF, More (placeholders).
- **AppBar:** Username centered (title), avatar on right (actions), back button (left), three-dot menu (unfriend option).

### Backend Changes

- **Message Entity:** Added `deliveryStatus` (enum), `expiresAt` (timestamp), `messageType` (enum), `mediaUrl` (text nullable).
- **SendMessageDto:** Added `expiresIn` (optional seconds).
- **SendPingDto:** New DTO with `recipientId`.
- **WebSocket Events:** `messageDelivered` (update delivery status), `newPing` (receive ping), `pingSent` (confirm ping sent).
- **ChatMessageService:** `handleSendPing` method creates ping messages with `messageType=PING`.

### Frontend Changes

- **MessageModel:** Added `deliveryStatus`, `expiresAt`, `messageType`, `mediaUrl` fields. Public `parseDeliveryStatus()` method.
- **ChatProvider:** `sendPing()`, `_handleMessageDelivered()`, `_handlePingReceived()`, `conversationDisappearingTimer`, `setConversationDisappearingTimer()`. Optimistic message updates with SENDING status. Emits `messageDelivered` when receiving messages.
- **SocketService:** `sendPing()`, `emitMessageDelivered()`, updated `sendMessage()` signature with `expiresIn`.
- **Dependencies:** `emoji_picker_flutter ^2.0.0`.

### Files Modified

- Backend: `message.entity.ts`, `messages.service.ts`, `chat-message.service.ts`, `chat.dto.ts`, `send-ping.dto.ts` (new), `chat.gateway.ts`
- Frontend: `message_model.dart`, `chat_provider.dart`, `socket_service.dart`, `chat_input_bar.dart`, `chat_message_bubble.dart`, `chat_detail_screen.dart`, `chat_action_tiles.dart` (new), `pubspec.yaml`

### Not Yet Implemented

- Drawing canvas screen (Task 3.6)
- Image upload endpoint + camera/drawing upload (Tasks 5.1, 5.2)

---

## 13. Recent Changes (2026-02-08)

- **Unread message badge (2026-02-08):** Conversation list now shows a badge with the count of unread messages (e.g. "4") when user B has new messages from A and was not in the app or not viewing that chat. Backend: `MessagesService.countUnreadForRecipient` counts messages where sender ≠ current user and deliveryStatus ≠ READ (excluding expired). `conversationsList` payload includes `unreadCount` per conversation. Frontend: `ChatProvider._unreadCounts` stores counts from backend + increments on `newMessage` when chat not active; clears on `openConversation`. `ConversationTile` displays orange badge with count (or "99+"). Files: messages.service.ts, conversation.mapper.ts, chat-conversation.service.ts, chat_provider.dart, conversation_tile.dart, conversations_screen.dart.

- **Messages disappear after switching chat (2026-02-08):** Preview in conversation list showed the latest message, but the chat window did not. Root cause: `messages.service.ts` `findByConversation` returned the 50 oldest messages (ASC). When conversation had 50+ messages, newest were excluded. Fix: fetch with `order: DESC`, take limit, then reverse to return most recent N messages in chronological order. messages.service.ts.

**2026-02-07:**

- **Docker image optimization (2026-02-07):**
  - **Frontend:** 7.64GB → 136MB (98% reduction). Added `frontend/.dockerignore` to exclude build artifacts (`build/`, `.dart_tool/`, `.git/`, etc.). Optimized both `Dockerfile` and `Dockerfile.dev` with layer caching (`COPY pubspec.* → RUN flutter pub get → COPY . .`) and cache cleanup (`flutter pub cache clean --force`). Production uses multi-stage build (Flutter build stage + nginx:alpine serve stage).
  - **Backend:** 644MB → 357MB (44% reduction). Expanded `backend/.dockerignore` to exclude tests, logs, IDE files. Optimized `Dockerfile` with multi-stage build: (1) Builder stage installs production deps, builds app, prunes to production; (2) Final stage copies only `node_modules`, `dist`, and `package.json`. Uses `npm ci --only=production` + `npm prune --production` to minimize dependencies.

- **Notifications at top (2026-02-07):** Error/success/feedback messages no longer cover the chat input bar. Added `showTopSnackBar()` in `widgets/top_snackbar.dart` (Overlay at top, 2.5s dismiss). Replaced all `ScaffoldMessenger.showSnackBar` usages in add_or_invitations_screen, friend_requests_screen, chat_action_tiles, chat_input_bar, drawing_canvas_screen, settings_screen, new_chat_screen with `showTopSnackBar(context, message, backgroundColor?: ...)`.

**2026-02-06:**

- **Disappearing messages fix (2026-02-06):** Three bugs fixed: (1) Timer reaching zero showed "Expired" text — added `ChatProvider.removeExpiredMessages()` called every 1s. (2) Messages disappeared on chat re-entry — root cause: TypeORM returns `expiresAt` as string; `string > Date` yields NaN in JS, filtering out all timed messages. Fix: `new Date(m.expiresAt).getTime() > nowMs`. (3) Added visual orange timer indicator bar in ChatInputBar showing active disappearing timer duration (e.g. "Disappearing messages: 1m"). Timer is sticky per conversation — set once, applies to all future messages. Files: chat_provider.dart, chat_detail_screen.dart, chat_message_bubble.dart, chat_input_bar.dart, messages.service.ts, chat-message.service.ts.

- **Docker hot-reload fix (2026-02-06):** Windows Docker volumes don't propagate inotify events. Backend: added `watchOptions` with polling to tsconfig.json. Frontend: polling watcher script (dev-entrypoint.sh) that detects file content changes and touches files to trigger inotify. Files: tsconfig.json, Dockerfile.dev, dev-entrypoint.sh.

- **Chat screen avatar blink fix (2026-02-05):** Avatar in chat header was blinking every ~1–2 s because ChatDetailScreen's Timer.periodic(1s) triggered full rebuilds and AvatarCircle used `DateTime.now()` in the image URL on every build. Fix: AvatarCircle keeps a stable cache-bust per profilePictureUrl. avatar_circle.dart.

**2026-02-01:** Conversations UI redesign (MainShell + BottomNav, ConversationsScreen header, AddOrInvitationsScreen). Code review; delete account cascade; avatar overwrite fix; no isOnline/active status.

---

## 14. Environment

| Var | Required | Purpose |
|-----|----------|---------|
| DB_HOST, DB_PORT, DB_USER, DB_PASS, DB_NAME | ✓ | PostgreSQL |
| JWT_SECRET | ✓ | JWT sign |
| CLOUDINARY_CLOUD_NAME, _API_KEY, _API_SECRET | ✓ | Avatars |
| PORT, NODE_ENV, ALLOWED_ORIGINS | — | Optional |

Frontend: BASE_URL dart define (default localhost:3000).

---

## 15. Bug Fix History (Lessons)

- **Delete Account FK:** Cascade delete dependents before user. users.service.ts, users.module.ts.
- **Avatar overwrite:** Skip deleteAvatar when same public_id. users.service.ts.
- **Socket cache:** enableForceNew() + cleanup in connect(). socket_service.dart, chat_provider.dart.
- **Multiple backends:** Kill local node; use one backend.
- **Session leak:** connect() clears state first; AuthGate clears on logout.
- **Unfriend:** find-then-remove. friends.service.ts.
- **deleteConversation:** Call unfriend() first. chat-conversation.service.ts.
- **Avatar blink in chat screen:** Use stable cache-bust per profilePictureUrl in AvatarCircle so parent rebuilds (e.g. Timer.periodic in ChatDetailScreen) don't change image URL and reload. avatar_circle.dart.
- **Disappearing messages — "Expired" not vanishing:** Frontend never removed expired messages from `_messages`. Fix: `ChatProvider.removeExpiredMessages()` called every 1s removes messages where `expiresAt < now`. `_getTimerText()` returns null (not "Expired"). chat_provider.dart, chat_message_bubble.dart, chat_detail_screen.dart.
- **Disappearing messages — vanish on chat re-entry:** Two-stage fix. (1) Added explicit `relations: ['sender']` and error handling. (2) **Root cause:** TypeORM returns `expiresAt` as string from pg driver; `string > Date` yields NaN in JavaScript, filtering out ALL timed messages. Fix: `new Date(m.expiresAt).getTime() > nowMs`. Also fixed frontend `onMessageHistory` to use `.removeWhere()` instead of `.where()` filter. messages.service.ts, chat-message.service.ts, chat_provider.dart.
- **Messages disappear after switching chat (preview shows, chat does not):** Backend `findByConversation` used `order: ASC` + `limit 50`, returning the 50 oldest messages. With 50+ messages, newest were never returned. Fix: `order: DESC`, `take`, then `.reverse()` to return the N most recent messages oldest-first. messages.service.ts.

---

## 16. Known Limitations

No user search. No typing indicators. No message edit/delete. No unique on (sender,receiver) — duplicate friend requests allowed. Last message not in conversationsList (client keeps lastMessages map). Message pagination: limit/offset, default 50.

---

## 17. Tech Debt

- Manual E2E scripts in scripts/ (Node, run against running backend). Not part of shipped app.
- Flutter tests: 9 (AppConstants, UserModel, ConversationModel, widget). `flutter test`.
- Constants in app_constants.dart: layoutBreakpointDesktop, conversationsRefreshDelay, messagePageSize, reconnect*.
- Reconnect: exponential backoff, max 5 attempts; token stored for reconnect; onDisconnect triggers unless intentional logout.

---

**Maintain this file.** After every code change, update the relevant section so an agent reading only CLAUDE.md understands the current state.
