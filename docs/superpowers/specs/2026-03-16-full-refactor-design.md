# Full Codebase Refactor — Domain-Driven Decomposition

**Date:** 2026-03-16
**Approach:** Aggressive domain-driven decomposition (frontend + backend)
**Branch:** TBD (separate branch)
**Tests:** Refactored alongside code; new unit tests for extracted classes

---

## 1. Frontend — Provider Decomposition

### Problem
`chat_provider.dart` (2,142 LOC) is a god-class managing state, encryption, messages, friends, reconnection, voice recording, and typing indicators.

### Solution — 5 Providers

| Provider | Responsibility | ~LOC |
|----------|---------------|------|
| `ConnectionProvider` | Socket lifecycle, reconnect, online status, event routing | ~300 |
| `ConversationsProvider` | Conversation list, unread counts, active conversation, disappearing timer | ~350 |
| `MessagingProvider` | Send/receive messages, optimistic updates, typing, pending content | ~500 |
| `FriendsProvider` | Friend requests, block/unblock, search users, friend list | ~400 |
| `EncryptionProvider` | E2E init, session management, encrypt/decrypt, key exchange, cache | ~400 |

### Communication

```
ConnectionProvider (socket ownership)
    | socket events routed to:
    |-- MessagingProvider (newMessage, messageSent, messageHistory...)
    |-- ConversationsProvider (conversationsList, openConversation...)
    |-- FriendsProvider (friendRequestsList, friendsList, blocked...)
    |-- EncryptionProvider (preKeyBundleResponse, preKeysLow...)

MessagingProvider -> uses EncryptionProvider (encrypt before send, decrypt on receive)
MessagingProvider -> updates ConversationsProvider (last message, unread)
FriendsProvider -> updates ConversationsProvider (unfriend removes conv)
```

**Mechanism:** `ChangeNotifierProxyProvider` for dependencies. `ConnectionProvider` is the root — creates socket, registers listeners, routes events to the appropriate providers via callbacks.

### State Migration (Complete)

| State | From | To |
|-------|------|----|
| `_activeConversationId` | ChatProvider | ConversationsProvider |
| `_conversations` / `_unreadCounts` | ChatProvider | ConversationsProvider |
| `_pendingOpenConversationId` / `consumePendingOpen()` | ChatProvider | ConversationsProvider |
| `_messages` / `_typingUsers` | ChatProvider | MessagingProvider |
| `_pendingSendContent` | ChatProvider | MessagingProvider |
| `_replyingToMessage` | ChatProvider | MessagingProvider |
| `_deletedMessageIds` | ChatProvider | MessagingProvider |
| `_decryptingHistory` / `_decryptHistoryGeneration` / `_incomingMessageQueue` | ChatProvider | MessagingProvider |
| `_delayedRetryTimer` / `_cancelDelayedRetryIfAny()` | ChatProvider | MessagingProvider |
| `countdownTickNotifier` / `isRecordingVoice` | ChatProvider | `recording_controller.dart` (widget-local state, not in provider — recording gesture + timer + state co-located) |
| `_blockedUsers` / `_blockedByUserIds` | ChatProvider | FriendsProvider |
| `_friends` / `_friendRequests` | ChatProvider | FriendsProvider |
| `_pendingFriendRequestSent` / `consumeFriendRequestSent()` | ChatProvider | FriendsProvider |
| `_pendingFriendAccepted` / `consumePendingFriendAccepted()` | ChatProvider | FriendsProvider |
| `_e2eInitialized` / `_pendingPreKeyFetches` | ChatProvider | EncryptionProvider |
| `_forceSessionRebuild` | ChatProvider | EncryptionProvider |
| `_decryptedContentCache` | ChatProvider | EncryptionProvider |
| `_generatingMoreKeys` | ChatProvider | EncryptionProvider |
| `_pushService` / `_pushInitialized` | ChatProvider | ConnectionProvider |
| Socket instance + reconnect logic | ChatProvider | ConnectionProvider |

### Connect/Reconnect Sequence

The current `connect()` is a monolithic transaction. After the split, `ConnectionProvider.connect(userId, token)` orchestrates the sequence:

```
ConnectionProvider.connect(userId, token):
  1. Cancel reconnect timers
  2. Determine isReconnect = (_currentUserId == userId)
  3. Call each provider's onConnect(isReconnect):
     - EncryptionProvider.onConnect(isReconnect)    // skip re-init if e2eInitialized
     - FriendsProvider.onConnect(isReconnect)        // clear if !isReconnect
     - ConversationsProvider.onConnect(isReconnect)  // preserve list on reconnect
     - MessagingProvider.onConnect(isReconnect)      // preserve messages on reconnect
  4. Dispose old socket, create new with enableForceNew()
  5. Register socket listeners (routed to sub-providers)
  6. On socket 'connect' event:
     - EncryptionProvider.initializeE2E()            // skips if _e2eInitialized
     - Emit getConversations, getFriendRequests, getFriends
     - If isReconnect && activeConversationId: emit getMessages
```

Each sub-provider implements `onConnect(bool isReconnect)` and `onDisconnect()`. ConnectionProvider calls them in order.

### Disconnect/Logout Sequence

```
ConnectionProvider.disconnect({bool isLogout = false}):
  1. Set intentionalDisconnect = true
  2. Cancel reconnect timers
  3. Call each provider's onDisconnect():
     - MessagingProvider.onDisconnect()       // cancel _delayedRetryTimer, clear typing
     - FriendsProvider.onDisconnect()          // no-op (state preserved for reconnect)
     - ConversationsProvider.onDisconnect()    // no-op (state preserved for reconnect)
     - EncryptionProvider.onDisconnect()       // clear _pendingPreKeyFetches, keep keys (NOT cleared on logout)
  4. Dispose socket
  5. If isLogout:
     - All providers clear state (conversations, messages, friends, etc.)
     - EncryptionProvider still does NOT clear keys (persist for re-login per CLAUDE.md)
     - Only clearEncryptionKeys() on account DELETION
```

### SocketService Refactoring

`SocketService.connect()` currently takes 30+ named callbacks. With ConnectionProvider as sole consumer, refactor to event-map pattern:

```dart
// Before: socket_service.connect(onMessage: ..., onTyping: ..., onFriendRequest: ..., ...)
// After:
socket_service.connect(token);
socket_service.on('newMessage', (data) => messagingProvider.onNewMessage(data));
socket_service.on('typingIndicator', (data) => messagingProvider.onTyping(data));
// ... etc — ConnectionProvider registers all listeners after connect
```

This eliminates the fragile 30+ parameter signature. Adding a new event = one `socket_service.on()` call in ConnectionProvider.

### Inter-Provider Interfaces

```dart
// ConversationsProvider — called by FriendsProvider and MessagingProvider
void removeConversationsForUser(int userId);
void clearActiveIfNeeded(int userId);  // clears active + messages if active conv is with userId
void updateLastMessage(int conversationId, MessageModel message);
void updateUnreadCount(int conversationId, int count);

// EncryptionProvider — called by MessagingProvider
Future<String> encrypt(int recipientId, String plaintext);
Future<String> decrypt(int senderId, String ciphertext);
Future<void> ensureSession(int recipientId);
bool get isE2EReady;

// ConnectionProvider — called by all providers for socket emit
void emit(String event, dynamic data);
int? get currentUserId;
bool get isConnected;

// MessagingProvider — called by FriendsProvider (unfriend/block clears messages)
void clearMessagesForConversation(int? conversationId);
```

### Cross-Domain Event Handlers

Events that touch multiple domains are handled by the PRIMARY provider, which calls explicit methods on other providers:

| Event | Primary Provider | Cross-Provider Calls |
|-------|-----------------|---------------------|
| `onUnfriended` | FriendsProvider | `conversations.removeConversationsForUser(userId)`, `messaging.clearMessagesForConversation(convId)` |
| `onYouWereBlocked` | FriendsProvider | same as unfriended |
| `onBlockedList` | FriendsProvider | `conversations.removeConversationsForUser(userId)` per blocked user |
| `onFriendRequestAccepted` | FriendsProvider | **NO getConversations/getFriends** (CLAUDE.md critical gotcha — backend emits lists) |
| `onNewMessage` | MessagingProvider | `conversations.updateUnreadCount(convId, +1)` |
| `onMessageHistory` | MessagingProvider | uses `encryption.decrypt()` per message (owns queue/generation logic) |

### ChangeNotifierProxyProvider Cascade Prevention

To avoid unnecessary rebuilds when ConnectionProvider notifies on every socket event:
- ConnectionProvider does NOT call `notifyListeners()` on event routing — it calls methods directly on sub-providers
- ConnectionProvider only notifies on connection state changes (connected/disconnected/reconnecting)
- Sub-providers notify only when their own state changes

### conversation_helpers.dart

Stays as a standalone utility file. Used by ConversationsProvider and screens (pure functions, no provider dependency).

---

## 2. Frontend — Widget Decomposition

### `chat_message_bubble.dart` (784 LOC) -> Composition Pattern

```
widgets/message/
  chat_message_bubble.dart       (~150 LOC) — wrapper: alignment, swipe-to-reply, long-press menu, reactions overlay
  message_content_factory.dart   (~40 LOC)  — switch(messageType) -> returns appropriate widget
  text_message_content.dart      (~120 LOC) — text + link preview
  image_message_content.dart     (~80 LOC)  — image + tap-to-fullscreen
  voice_message_content.dart     (~80 LOC)  — reuse playback logic
  gif_message_content.dart       (~60 LOC)  — GIF rendering
  file_message_content.dart      (~60 LOC)  — icon + filename + tap-to-open
  ping_message_content.dart      (~40 LOC)  — ping animation
  message_metadata_row.dart      (~60 LOC)  — time + delivery icon + timer (shared)
```

**Principle:** Each `*_content.dart` is a pure widget — receives `MessageModel`, renders. Zero business logic, zero socket calls.

### `chat_input_bar.dart` (809 LOC) -> Extraction

```
widgets/input/
  chat_input_bar.dart            (~300 LOC) — text field + send button + orchestration
  recording_controller.dart      (~200 LOC) — mic hold logic, timer, cancel gesture
  attachment_handler.dart        (~150 LOC) — image/file picker, upload, type detection
  reply_preview_bar.dart         (~80 LOC)  — reply-to preview strip
```

### `voice_message_bubble.dart` (617 LOC) -> Extract Playback

```
widgets/message/
  voice_message_content.dart     (~80 LOC)  — UI shell
widgets/audio/
  playback_controller.dart       (~200 LOC) — just_audio lifecycle, position tracking, speed toggle
  waveform_display.dart          (~150 LOC) — waveform rendering + scrub gesture
```

---

## 3. Backend — Gateway + Services

### `chat.gateway.ts` (462 LOC, 29 handlers) -> Thin Gateway

Every handler becomes 1-2 lines of pure delegation. Validation, try/catch, logging — moved to services. Gateway drops from ~462 to ~150 LOC.

**Currently inline handlers that need extraction:**
- `handleTyping` / `handleRecordingVoice` (relay logic) -> `chat-presence.service.ts` (~60 LOC)
- `handleBlockUser` / `handleUnblockUser` / `handleGetBlockedList` (business logic) -> `chat-block.service.ts`

### `chat-message.service.ts` (522 LOC) -> Split

```
chat/services/
  chat-message.service.ts        (~300 LOC) — send, delivered, read, delete
  chat-reaction.service.ts       (~100 LOC) — addReaction, removeReaction
  chat-link-preview.service.ts   (~120 LOC) — fetchAndEmit (partially isolated already)
```

### `chat-friend-request.service.ts` (503 LOC) -> Split

```
chat/services/
  chat-friend-request.service.ts (~250 LOC) — send, accept, reject, get
  chat-block.service.ts          (~150 LOC) — block, unblock, getBlocked
  chat-search.service.ts         (~80 LOC)  — searchUsers
```

### `messages.service.ts` (428 LOC) -> Keep as-is

At 428 LOC this file is under the 500 LOC threshold and has good cohesion. Splitting it would add DI wiring complexity for marginal gains. Revisit if it grows past 500 LOC.

---

## 4. Directory Structure After Refactor

### Frontend `lib/`

```
providers/
  connection_provider.dart
  conversations_provider.dart
  messaging_provider.dart
  friends_provider.dart
  encryption_provider.dart
  auth_provider.dart              (unchanged)
  settings_provider.dart          (unchanged)
  chat_reconnect_manager.dart     (unchanged, used by ConnectionProvider)

widgets/
  message/
    chat_message_bubble.dart
    message_content_factory.dart
    text_message_content.dart
    image_message_content.dart
    voice_message_content.dart
    gif_message_content.dart
    file_message_content.dart
    ping_message_content.dart
    message_metadata_row.dart
  input/
    chat_input_bar.dart
    recording_controller.dart
    attachment_handler.dart
    reply_preview_bar.dart
  audio/
    playback_controller.dart
    waveform_display.dart
  conversation_tile.dart          (unchanged)
  avatar_circle.dart              (unchanged)
  top_snackbar.dart               (unchanged)
```

### Backend `src/chat/`

```
chat/
  chat.gateway.ts                 (~150 LOC, thin)
  services/
    chat-message.service.ts
    chat-reaction.service.ts
    chat-link-preview.service.ts
    chat-presence.service.ts          (typing, recording-voice relay)
    chat-conversation.service.ts    (unchanged)
    chat-friend-request.service.ts
    chat-block.service.ts
    chat-search.service.ts
    chat-key-exchange.service.ts    (unchanged)
    chat-validation.service.ts      (unchanged)
```

---

## 5. Summary

| # | Section | What | Effect |
|---|---------|------|--------|
| 1 | Frontend Providers | `chat_provider.dart` (2142) -> 5 providers | Max ~500 LOC per provider |
| 2 | Frontend Widgets | 3 files >600 LOC -> ~15 files <300 LOC | Composition pattern, per-type renderers |
| 3 | Backend Services | 4 files >400 LOC -> ~10 files <300 LOC | Thin gateway, focused services |
| 4 | Directory Structure | New subfolders: `widgets/message/`, `widgets/input/`, `widgets/audio/` | Clear organization |

### Error Handling

Each provider manages its own error state. Pattern: try/catch in handler → set `_error` field → `notifyListeners()`. Screens read errors from the relevant provider (`messagingProvider.error`, `friendsProvider.error`). No shared error bus — keeps providers independent.

### Provider Tree in `main.dart`

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ChangeNotifierProvider(create: (_) => ConnectionProvider()),
    ChangeNotifierProxyProvider<ConnectionProvider, EncryptionProvider>(...),
    ChangeNotifierProxyProvider2<ConnectionProvider, EncryptionProvider, MessagingProvider>(...),
    ChangeNotifierProxyProvider<ConnectionProvider, FriendsProvider>(...),
    ChangeNotifierProxyProvider<ConnectionProvider, ConversationsProvider>(...),
  ],
)
// Order matters: ConnectionProvider first, then Encryption, then the rest
// MessagingProvider depends on both Connection + Encryption
// FriendsProvider and ConversationsProvider depend on Connection
// Cross-provider method calls (e.g., Friends -> Conversations) resolved via context.read in handlers
```

### Phase Exit Criteria

| Phase | Done when |
|-------|-----------|
| 1 | All 152 backend tests pass, gateway handlers are 1-2 lines each |
| 2 | EncryptionProvider extracted, encryption tests pass, E2E works in browser |
| 3 | FriendsProvider extracted, friend request/block flows work manually |
| 4 | All 5 providers wired, old ChatProvider removed, all 61 frontend tests pass |
| 5 | Widget files decomposed, no widget >300 LOC, UI visually identical |
| 6 | All `context.read<ChatProvider>` replaced, app fully functional |

**Constraints:**
- No file >500 LOC after refactor (total LOC will grow ~15-20% from boilerplate — acceptable)
- New message type = 1 new `*_content.dart` + factory registration
- New WS event = 1 line in gateway + handler in appropriate service
- Tests adapted in the same step as migrated logic
- All CLAUDE.md gotchas preserved through refactor

---

## 6. Migration Strategy

Phased approach — each phase is independently testable and mergeable:

| Phase | What | Risk | Dependencies |
|-------|------|------|-------------|
| **1** | Backend: thin gateway + extract presence/block/search/reaction services | Low | None |
| **2** | Frontend: extract `EncryptionProvider` (least UI coupling, pure async) | Low | None |
| **3** | Frontend: extract `FriendsProvider` (clear domain boundary) | Medium | Phase 2 (encryption interface) |
| **4** | Frontend: split `ConnectionProvider` + `ConversationsProvider` + `MessagingProvider` (most coupled) | High | Phases 2-3 |
| **5** | Frontend: decompose widgets (`chat_message_bubble`, `chat_input_bar`, `voice_message_bubble`) | Low | Phase 4 (providers stable) |
| **6** | Update all screen `context.read/watch` calls, remove old `ChatProvider` | Medium | All above |

During phases 2-4, `ChatProvider` can temporarily act as a facade that delegates to new providers, keeping existing screen code working until phase 6.

---

## 7. CLAUDE.md Gotchas Preservation Checklist

Every gotcha must be explicitly verified during implementation:

| Gotcha | Target Provider | Notes |
|--------|----------------|-------|
| `enableForceNew()` on reconnect | ConnectionProvider (via SocketService) | SocketService unchanged, but verify ConnectionProvider uses it |
| Provider can't call Navigator — `consumePendingOpen()` | ConversationsProvider | Pattern must be preserved exactly |
| `consumeFriendRequestSent()` / `consumePendingFriendAccepted()` | FriendsProvider | Consumed by screens, not other providers |
| Do NOT call `getConversations/getFriends` in `onFriendRequestAccepted` | FriendsProvider | **Critical** — backend already emits lists |
| Reconnect must NOT clear `_conversations/_friends` | ConnectionProvider orchestrates via `onConnect(isReconnect)` | Each provider preserves state when `isReconnect=true` |
| `_pendingSendContent` survives `_messages` overwrites | MessagingProvider | Separate map, never cleared by messageHistory |
| `_initializeE2E` skips when `_e2eInitialized = true` | EncryptionProvider | Prevents `[Decryption failed]` on reconnect |
| `_decryptingHistory` queue ordering | MessagingProvider | Queue + generation counter stay together |
| `_delayedRetryTimer` cancel on connect/logout | MessagingProvider | `_cancelDelayedRetryIfAny()` in onConnect/onDisconnect |
| `_forceSessionRebuild` on decrypt failure | EncryptionProvider | Auto-accepts new identities, resets broken sessions |
| `_decryptedContentCache` (SharedPreferences) | EncryptionProvider | Cache-first history decryption |
| `clearStatus()` in AuthProvider | AuthProvider (unchanged) | Called from auth_screen.dart — DO NOT DELETE |
| `_pendingSendContent` explicit type `<String, dynamic>` | MessagingProvider | Prevents DDC/JS IdentityMap subtype errors on web |
