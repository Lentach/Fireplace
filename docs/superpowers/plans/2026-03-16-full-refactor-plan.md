# Full Codebase Refactor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the Fireplace codebase along domain boundaries — splitting the frontend god-class `chat_provider.dart` (2142 LOC) into 5 focused providers, decomposing 3 oversized widgets into composition patterns, and thinning the backend gateway with extracted services.

**Architecture:** Domain-driven decomposition. Frontend: 5 ChangeNotifier providers (Connection, Conversations, Messaging, Friends, Encryption) wired via ChangeNotifierProxyProvider. Backend: thin WebSocket gateway delegating to focused services. Widgets: composition pattern with factory + per-type content renderers.

**Tech Stack:** Flutter 3.x (Provider, ChangeNotifier), NestJS 11 (TypeORM, Socket.IO), PostgreSQL 16, libsignal_protocol_dart

**Spec:** `docs/superpowers/specs/2026-03-16-full-refactor-design.md`

**Branch:** `refactor/domain-driven-decomposition`

---

## Chunk 1: Backend — Thin Gateway + Extract Services (Phase 1)

This chunk extracts inline gateway logic into dedicated services and splits large service files. Low risk — backend already has good service delegation patterns.

**Test command:** `cd backend && npm test` (152 tests, 17 suites)

---

### Task 1.1: Extract `chat-presence.service.ts` (typing + recording-voice relay)

**Files:**
- Create: `backend/src/chat/services/chat-presence.service.ts`
- Create: `backend/src/chat/services/chat-presence.service.spec.ts`
- Modify: `backend/src/chat/chat.gateway.ts:193-248` (inline typing + recording handlers)
- Modify: `backend/src/chat/chat.module.ts:32-39` (add provider)

- [ ] **Step 1: Create `chat-presence.service.ts` with typing + recording handlers**

Extract the inline logic from `chat.gateway.ts` lines 193-211 (handleTyping) and 229-248 (handleRecordingVoice) into a new service.

```typescript
// backend/src/chat/services/chat-presence.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { validateDto } from '../utils/dto.validator';
import { TypingDto } from '../dto/typing.dto';
import { RecordingVoiceDto } from '../dto/recording-voice.dto';

@Injectable()
export class ChatPresenceService {
  private readonly logger = new Logger(ChatPresenceService.name);

  async handleTyping(
    server: Server,
    client: Socket,
    payload: any,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    try {
      const dto = await validateDto(TypingDto, payload);
      const userId: number = client.data.user?.id;
      if (!userId) return;
      const recipientSocketId = onlineUsers.get(dto.recipientId);
      if (recipientSocketId) {
        server.to(recipientSocketId).emit('partnerTyping', {
          conversationId: dto.conversationId,
          userId,
        });
      }
    } catch (error) {
      this.logger.error(`Typing error: ${error.message}`);
    }
  }

  async handleRecordingVoice(
    server: Server,
    client: Socket,
    payload: any,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    try {
      const dto = await validateDto(RecordingVoiceDto, payload);
      const userId: number = client.data.user?.id;
      if (!userId) return;
      const recipientSocketId = onlineUsers.get(dto.recipientId);
      if (recipientSocketId) {
        server.to(recipientSocketId).emit('partnerRecordingVoice', {
          conversationId: dto.conversationId,
          userId,
          isRecording: dto.isRecording,
        });
      }
    } catch (error) {
      this.logger.error(`Recording voice error: ${error.message}`);
    }
  }
}
```

- [ ] **Step 2: Write tests for `chat-presence.service.ts`**

```typescript
// backend/src/chat/services/chat-presence.service.spec.ts
import { ChatPresenceService } from './chat-presence.service';

describe('ChatPresenceService', () => {
  let service: ChatPresenceService;
  let mockServer: any;
  let mockClient: any;
  let onlineUsers: Map<number, string>;

  beforeEach(() => {
    service = new ChatPresenceService();
    mockServer = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
    };
    mockClient = { data: { user: { id: 1 } } };
    onlineUsers = new Map([[2, 'socket-2']]);
  });

  describe('handleTyping', () => {
    it('should emit partnerTyping to recipient', async () => {
      await service.handleTyping(mockServer, mockClient, {
        recipientId: 2,
        conversationId: 10,
      }, onlineUsers);

      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('partnerTyping', {
        conversationId: 10,
        userId: 1,
      });
    });

    it('should not emit if recipient offline', async () => {
      await service.handleTyping(mockServer, mockClient, {
        recipientId: 99,
        conversationId: 10,
      }, onlineUsers);

      expect(mockServer.to).not.toHaveBeenCalled();
    });
  });

  describe('handleRecordingVoice', () => {
    it('should emit partnerRecordingVoice to recipient', async () => {
      await service.handleRecordingVoice(mockServer, mockClient, {
        recipientId: 2,
        conversationId: 10,
        isRecording: true,
      }, onlineUsers);

      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('partnerRecordingVoice', {
        conversationId: 10,
        userId: 1,
        isRecording: true,
      });
    });
  });
});
```

- [ ] **Step 3: Run tests to verify presence service works**

Run: `cd backend && npx jest --testPathPattern=chat-presence.service.spec --verbose`
Expected: All 3 tests PASS

- [ ] **Step 4: Update gateway to delegate typing + recording to presence service**

In `backend/src/chat/chat.gateway.ts`, replace inline handlers (lines 193-211, 229-248) with delegation:

```typescript
// Replace handleTyping (lines 193-211) with:
@SubscribeMessage('typing')
async handleTyping(@ConnectedSocket() client: Socket, @MessageBody() payload: any) {
  return this.presenceService.handleTyping(this.server, client, payload, this.onlineUsers);
}

// Replace handleRecordingVoice (lines 229-248) with:
@SubscribeMessage('recordingVoice')
async handleRecordingVoice(@ConnectedSocket() client: Socket, @MessageBody() payload: any) {
  return this.presenceService.handleRecordingVoice(this.server, client, payload, this.onlineUsers);
}
```

Add `ChatPresenceService` to constructor injection and import.

- [ ] **Step 5: Register presence service in chat module**

In `backend/src/chat/chat.module.ts`, add `ChatPresenceService` to `providers` array.

- [ ] **Step 6: Run full backend test suite**

Run: `cd backend && npm test`
Expected: All 152 tests PASS

- [ ] **Step 7: Commit**

```bash
git add backend/src/chat/services/chat-presence.service.ts backend/src/chat/services/chat-presence.service.spec.ts backend/src/chat/chat.gateway.ts backend/src/chat/chat.module.ts
git commit -m "refactor(backend): extract chat-presence.service for typing + recording relay"
```

---

### Task 1.2: Extract `chat-block.service.ts` (block/unblock/getBlocked)

**Files:**
- Create: `backend/src/chat/services/chat-block.service.ts`
- Create: `backend/src/chat/services/chat-block.service.spec.ts`
- Modify: `backend/src/chat/chat.gateway.ts:410-461` (inline block handlers)
- Modify: `backend/src/chat/chat.module.ts`

- [ ] **Step 1: Create `chat-block.service.ts`**

Extract inline logic from `chat.gateway.ts` lines 410-461 (handleBlockUser, handleUnblockUser, handleGetBlockedList).

```typescript
// backend/src/chat/services/chat-block.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { BlockedService } from '../../blocked/blocked.service';
import { UserMapper } from '../mappers/user.mapper';
import { validateDto } from '../utils/dto.validator';
import { BlockUserDto } from '../dto/chat.dto';

@Injectable()
export class ChatBlockService {
  private readonly logger = new Logger(ChatBlockService.name);

  constructor(private readonly blockedService: BlockedService) {}

  async handleBlockUser(
    server: Server,
    client: Socket,
    payload: any,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;
    try {
      const dto = validateDto(BlockUserDto, payload);

      if (dto.userId === userId) {
        client.emit('error', { message: 'Cannot block yourself' });
        return;
      }

      await this.blockedService.block(userId, dto.userId);

      const blocked = await this.blockedService.getBlockedUsers(userId);
      client.emit('blockedList', blocked.map(u => UserMapper.toPayload(u)));

      const blockedUserSocketId = onlineUsers.get(dto.userId);
      if (blockedUserSocketId) {
        server.to(blockedUserSocketId).emit('youWereBlocked', { userId });
      }
    } catch (error) {
      this.logger.error(`Block user error: ${error.message}`);
      client.emit('error', { message: error?.message || 'Failed to block user' });
    }
  }

  async handleUnblockUser(
    client: Socket,
    payload: any,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;
    try {
      const dto = validateDto(BlockUserDto, payload);

      await this.blockedService.unblock(userId, dto.userId);

      const blocked = await this.blockedService.getBlockedUsers(userId);
      client.emit('blockedList', blocked.map(u => UserMapper.toPayload(u)));
    } catch (error) {
      this.logger.error(`Unblock user error: ${error.message}`);
      client.emit('error', { message: error?.message || 'Failed to unblock user' });
    }
  }

  async handleGetBlockedList(client: Socket): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;
    const blocked = await this.blockedService.getBlockedUsers(userId);
    client.emit('blockedList', blocked.map(u => UserMapper.toPayload(u)));
  }
}
```

**IMPORTANT:** DTO field is `dto.userId` (not `targetUserId`). Payload for `youWereBlocked` is `{ userId }` (not `{ blockedByUserId }`). User ID from `client.data.user?.id`. Must match existing gateway behavior exactly.

- [ ] **Step 2: Write tests for `chat-block.service.ts`**

```typescript
// backend/src/chat/services/chat-block.service.spec.ts
import { ChatBlockService } from './chat-block.service';

describe('ChatBlockService', () => {
  let service: ChatBlockService;
  let mockBlockedService: any;
  let mockServer: any;
  let mockClient: any;
  let onlineUsers: Map<number, string>;

  beforeEach(() => {
    mockBlockedService = {
      block: jest.fn(),
      unblock: jest.fn(),
      getBlockedUsers: jest.fn().mockResolvedValue([]),
    };
    service = new ChatBlockService(mockBlockedService);
    mockServer = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
    };
    mockClient = { data: { user: { id: 1 } }, emit: jest.fn() };
    onlineUsers = new Map([[2, 'socket-2']]);
  });

  describe('handleBlockUser', () => {
    it('should block user and emit blockedList + youWereBlocked', async () => {
      await service.handleBlockUser(mockServer, mockClient, {
        userId: 2,
      }, onlineUsers);

      expect(mockBlockedService.block).toHaveBeenCalledWith(1, 2);
      expect(mockClient.emit).toHaveBeenCalledWith('blockedList', []);
      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('youWereBlocked', { userId: 1 });
    });

    it('should reject self-block', async () => {
      await service.handleBlockUser(mockServer, mockClient, {
        userId: 1,
      }, onlineUsers);

      expect(mockBlockedService.block).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('error', { message: 'Cannot block yourself' });
    });
  });

  describe('handleUnblockUser', () => {
    it('should unblock and emit updated blockedList', async () => {
      await service.handleUnblockUser(mockClient, {
        userId: 2,
      });

      expect(mockBlockedService.unblock).toHaveBeenCalledWith(1, 2);
      expect(mockClient.emit).toHaveBeenCalledWith('blockedList', []);
    });
  });

  describe('handleGetBlockedList', () => {
    it('should emit blockedList', async () => {
      await service.handleGetBlockedList(mockClient);

      expect(mockBlockedService.getBlockedUsers).toHaveBeenCalledWith(1);
      expect(mockClient.emit).toHaveBeenCalledWith('blockedList', []);
    });
  });
});
```

- [ ] **Step 3: Run block service tests**

Run: `cd backend && npx jest --testPathPattern=chat-block.service.spec --verbose`
Expected: All 4 tests PASS

- [ ] **Step 4: Update gateway to delegate block handlers**

In `backend/src/chat/chat.gateway.ts`, replace lines 410-461 with thin delegation:

```typescript
@SubscribeMessage('blockUser')
async handleBlockUser(@ConnectedSocket() client: Socket, @MessageBody() payload: any) {
  return this.blockService.handleBlockUser(this.server, client, payload, this.onlineUsers);
}

@SubscribeMessage('unblockUser')
async handleUnblockUser(@ConnectedSocket() client: Socket, @MessageBody() payload: any) {
  return this.blockService.handleUnblockUser(this.server, client, payload);
}

@SubscribeMessage('getBlockedList')
async handleGetBlockedList(@ConnectedSocket() client: Socket) {
  return this.blockService.handleGetBlockedList(client);
}
```

Add `ChatBlockService` to constructor injection. Remove `BlockedService` direct import from gateway (now only used by ChatBlockService).

- [ ] **Step 5: Register in chat module**

Add `ChatBlockService` to `providers` in `backend/src/chat/chat.module.ts`.

- [ ] **Step 6: Run full backend test suite**

Run: `cd backend && npm test`
Expected: All 152 tests PASS (+ new tests)

- [ ] **Step 7: Commit**

```bash
git add backend/src/chat/services/chat-block.service.ts backend/src/chat/services/chat-block.service.spec.ts backend/src/chat/chat.gateway.ts backend/src/chat/chat.module.ts
git commit -m "refactor(backend): extract chat-block.service for block/unblock/getBlocked"
```

---

### Task 1.3: Extract `chat-search.service.ts` from friend-request service

**Files:**
- Create: `backend/src/chat/services/chat-search.service.ts`
- Create: `backend/src/chat/services/chat-search.service.spec.ts`
- Modify: `backend/src/chat/services/chat-friend-request.service.ts:120-143` (remove handleSearchUsers)
- Modify: `backend/src/chat/chat.gateway.ts:342-348` (point to new service)
- Modify: `backend/src/chat/chat.module.ts`

- [ ] **Step 1: Read current `handleSearchUsers` in chat-friend-request.service.ts**

Read `backend/src/chat/services/chat-friend-request.service.ts` lines 120-143 to get exact implementation.

- [ ] **Step 2: Create `chat-search.service.ts`**

Move `handleSearchUsers` (lines 120-143) into its own service. The method depends on `UsersService` and `FriendsService` — inject those.

- [ ] **Step 3: Write test for search service**

Test: search by handle, search self (rejected), search for existing friend (filtered).

- [ ] **Step 4: Run search service tests**

Run: `cd backend && npx jest --testPathPattern=chat-search.service.spec --verbose`
Expected: PASS

- [ ] **Step 5: Remove `handleSearchUsers` from chat-friend-request.service.ts**

Delete lines 120-143 and any imports only used by that method.

- [ ] **Step 6: Update gateway to use ChatSearchService for searchUsers**

Change `this.friendRequestService.handleSearchUsers(...)` to `this.searchService.handleSearchUsers(...)` in gateway.

- [ ] **Step 7: Register ChatSearchService in chat.module.ts**

- [ ] **Step 8: Run full backend test suite**

Run: `cd backend && npm test`
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add backend/src/chat/services/chat-search.service.ts backend/src/chat/services/chat-search.service.spec.ts backend/src/chat/services/chat-friend-request.service.ts backend/src/chat/chat.gateway.ts backend/src/chat/chat.module.ts
git commit -m "refactor(backend): extract chat-search.service from friend-request service"
```

---

### Task 1.4: Extract `chat-reaction.service.ts` from message service

**Context:** The gateway already delegates reaction handlers to `chatMessageService` (lines 213-227 are 1-2 line calls). The work here is moving the handler *implementations* from `chat-message.service.ts` into a dedicated `chat-reaction.service.ts`, then re-pointing the gateway DI target.

**Files:**
- Create: `backend/src/chat/services/chat-reaction.service.ts`
- Create: `backend/src/chat/services/chat-reaction.service.spec.ts`
- Modify: `backend/src/chat/services/chat-message.service.ts:449-521` (remove reaction methods)
- Modify: `backend/src/chat/chat.gateway.ts:213-227` (change DI target from messageService to reactionService)
- Modify: `backend/src/chat/chat.module.ts`

- [ ] **Step 1: Read current reaction methods in chat-message.service.ts**

Read `backend/src/chat/services/chat-message.service.ts` lines 449-521 (`handleAddReaction`, `handleRemoveReaction`).

- [ ] **Step 2: Create `chat-reaction.service.ts`**

Move both reaction handlers into own service. Dependencies: `MessagesService` (for `addOrUpdateReaction`, `removeReaction`), plus `onlineUsers` map for emitting to both parties.

- [ ] **Step 3: Write tests for reaction service**

Test: add reaction emits to both, remove reaction emits to both, reaction on nonexistent message (error).

- [ ] **Step 4: Run reaction service tests**

Run: `cd backend && npx jest --testPathPattern=chat-reaction.service.spec --verbose`
Expected: PASS

- [ ] **Step 5: Remove reaction methods from chat-message.service.ts**

Delete lines 449-521 and unused imports.

- [ ] **Step 6: Update gateway DI: change `this.chatMessageService.handleAddReaction/handleRemoveReaction` → `this.reactionService.*`**

The gateway handlers at lines 213-227 are already thin delegation — only the injected service name changes.

- [ ] **Step 7: Register ChatReactionService in chat.module.ts**

- [ ] **Step 8: Run full backend test suite**

Run: `cd backend && npm test`
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add backend/src/chat/services/chat-reaction.service.ts backend/src/chat/services/chat-reaction.service.spec.ts backend/src/chat/services/chat-message.service.ts backend/src/chat/chat.gateway.ts backend/src/chat/chat.module.ts
git commit -m "refactor(backend): extract chat-reaction.service from message service"
```

---

### Task 1.5: Extract `chat-link-preview.service.ts` from message service

**Files:**
- Create: `backend/src/chat/services/chat-link-preview.service.ts`
- Create: `backend/src/chat/services/chat-link-preview.service.spec.ts`
- Modify: `backend/src/chat/services/chat-message.service.ts:113-135` (extract link preview fire-and-forget)
- Modify: `backend/src/chat/chat.module.ts`

- [ ] **Step 1: Read link preview logic in chat-message.service.ts**

Read the fire-and-forget async link preview fetch at lines 113-135 of `chat-message.service.ts`.

- [ ] **Step 2: Create `chat-link-preview.service.ts`**

Extract the link preview fetch + emit logic. Dependencies: `LinkPreviewService` (existing), plus socket emit.

- [ ] **Step 3: Write test for `chat-link-preview.service.ts`**

Test: link preview fetched and emitted to both users; skipped when `encryptedContent` is present (CLAUDE.md gotcha: server can't read encrypted content).

- [ ] **Step 4: Run link preview service tests**

Run: `cd backend && npx jest --testPathPattern=chat-link-preview.service.spec --verbose`
Expected: PASS

- [ ] **Step 5: Update chat-message.service.ts to use ChatLinkPreviewService**

Replace the inline link preview logic with `this.chatLinkPreviewService.fetchAndEmitIfNeeded(...)`.

- [ ] **Step 6: Register in chat.module.ts**

- [ ] **Step 7: Run full backend test suite**

Run: `cd backend && npm test`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add backend/src/chat/services/chat-link-preview.service.ts backend/src/chat/services/chat-message.service.ts backend/src/chat/chat.module.ts
git commit -m "refactor(backend): extract chat-link-preview.service from message service"
```

---

### Task 1.6: Verify gateway is thin + final backend cleanup

- [ ] **Step 1: Count gateway lines**

Run: `wc -l backend/src/chat/chat.gateway.ts`
Expected: ~150-180 lines (down from 463)

- [ ] **Step 2: Verify every handler is 1-3 lines of delegation**

Read `backend/src/chat/chat.gateway.ts` and verify no handler has inline business logic (only `handleConnection` and `handleDisconnect` should have more than 3 lines).

- [ ] **Step 3: Run full backend test suite one final time**

Run: `cd backend && npm test`
Expected: All 152+ tests PASS

- [ ] **Step 4: Commit any cleanup**

```bash
git add -A backend/
git commit -m "refactor(backend): phase 1 complete — thin gateway, all services extracted"
```

---

### Phase 1 Exit Criteria Check

- [ ] All 152+ backend tests PASS
- [ ] Gateway handlers are 1-3 lines each (only handleConnection/handleDisconnect have more)
- [ ] Gateway LOC ~150-180 (down from 463)
- [ ] New services: chat-presence, chat-block, chat-search, chat-reaction, chat-link-preview — each with tests

---

## Chunk 2: Frontend — Extract EncryptionProvider (Phase 2)

Lowest-risk frontend extraction. EncryptionProvider has the least UI coupling — it exposes pure async functions (encrypt/decrypt/ensureSession) and manages key state. No Navigator calls, no widget rebuilds from its state.

**Test command:** `cd frontend && flutter test && flutter analyze`

---

### Task 2.1: Create `EncryptionProvider` skeleton with state + interface

**Files:**
- Create: `frontend/lib/providers/encryption_provider.dart`

- [ ] **Step 1: Create EncryptionProvider with all E2E state fields**

Move these fields from `chat_provider.dart`:
- `_encryptionService` (line 36)
- `_e2eInitialized` (line 37)
- `_pendingPreKeyFetches` (line 38)
- `_generatingMoreKeys` (line 39)
- `_forceSessionRebuild` (line 47)
- `_decryptedContentCache` (line 48)

```dart
// frontend/lib/providers/encryption_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/encryption_service.dart';
import '../models/message_model.dart';

class EncryptionProvider extends ChangeNotifier {
  final EncryptionService _encryptionService = EncryptionService();

  bool _e2eInitialized = false;
  final Map<int, Completer<Map<String, dynamic>?>> _pendingPreKeyFetches = {};
  bool _generatingMoreKeys = false;
  final Set<int> _forceSessionRebuild = {};
  final Map<int, MessageModel> _decryptedContentCache = {};

  String? _error;

  // --- Public interface (called by MessagingProvider) ---
  // Methods, not raw data — encapsulation per spec inter-provider interfaces
  bool get isE2EReady => _e2eInitialized;
  String? get error => _error;

  /// Encrypt plaintext for a recipient. Called by MessagingProvider.
  Future<String> encrypt(int recipientId, String plaintext) async {
    return _encryptionService.encrypt(recipientId, plaintext);
  }

  /// Decrypt ciphertext from a sender. Called by MessagingProvider.
  Future<String> decrypt(int senderId, String ciphertext) async {
    return _encryptionService.decrypt(senderId, ciphertext);
  }

  /// Ensure session exists with recipient. Called by MessagingProvider before encrypt.
  Future<void> ensureSession(int recipientId) async {
    // Session establishment logic (moved from ChatProvider._ensureSession)
    // Uses _pendingPreKeyFetches, _forceSessionRebuild internally
  }

  /// Check if session needs rebuild for recipient.
  bool needsSessionRebuild(int recipientId) => _forceSessionRebuild.contains(recipientId);
  void clearSessionRebuild(int recipientId) => _forceSessionRebuild.remove(recipientId);

  /// Cache management for decrypted messages (SharedPreferences-backed).
  MessageModel? getCachedDecryption(int messageId) => _decryptedContentCache[messageId];
  void cacheDecryption(int messageId, MessageModel msg) => _decryptedContentCache[messageId] = msg;

  /// Access encryption service directly (needed for initializeE2E internals).
  /// TODO: Minimize direct access as more methods are extracted.
  EncryptionService get encryptionService => _encryptionService;

  // --- Lifecycle (called by ConnectionProvider) ---
  void onConnect(bool isReconnect) {
    if (!isReconnect) {
      // Fresh connect — reset E2E state but keep keys
      _e2eInitialized = false;
      _pendingPreKeyFetches.clear();
      _forceSessionRebuild.clear();
      _decryptedContentCache.clear();
      _generatingMoreKeys = false;
    }
    // On reconnect: skip — _e2eInitialized stays true per CLAUDE.md
  }

  void onDisconnect() {
    _pendingPreKeyFetches.clear();
    // Keys NOT cleared on logout (CLAUDE.md gotcha)
  }

  void clearAll() {
    _e2eInitialized = false;
    _pendingPreKeyFetches.clear();
    _forceSessionRebuild.clear();
    _decryptedContentCache.clear();
    _generatingMoreKeys = false;
    notifyListeners();
  }

  // Mark E2E as initialized (called after successful _initializeE2E)
  void markE2EInitialized() {
    _e2eInitialized = true;
  }

  @override
  void dispose() {
    _pendingPreKeyFetches.clear();
    super.dispose();
  }
}
```

- [ ] **Step 2: Run frontend tests to verify no regressions**

Run: `cd frontend && flutter test`
Expected: All 61 tests PASS (new file doesn't break anything)

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/encryption_provider.dart
git commit -m "refactor(frontend): create EncryptionProvider skeleton with E2E state"
```

---

### Task 2.2: Wire EncryptionProvider into provider tree + ChatProvider facade

**Files:**
- Modify: `frontend/lib/main.dart:28-33` (add EncryptionProvider to MultiProvider)
- Modify: `frontend/lib/providers/chat_provider.dart` (delegate E2E state to EncryptionProvider)

- [ ] **Step 1: Add EncryptionProvider to MultiProvider in main.dart**

```dart
// In main.dart, update MultiProvider:
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => EncryptionProvider()),
    ChangeNotifierProvider(create: (_) => ChatProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
  ],
  // ...
)
```

- [ ] **Step 2: Update ChatProvider to accept and delegate to EncryptionProvider**

Add `EncryptionProvider? _encryptionProvider;` field. Add `setEncryptionProvider(EncryptionProvider ep)` method. In `connect()`, call `_encryptionProvider?.onConnect(isReconnect)`. In `disconnect()`, call `_encryptionProvider?.onDisconnect()`.

The facade pattern: ChatProvider still exposes the same public API to screens, but internally delegates E2E state to EncryptionProvider. This keeps all existing `context.read<ChatProvider>()` calls working.

- [ ] **Step 3: Wire in AuthGate or MainShell**

In the widget that has access to both providers (likely `main_shell_screen.dart` or `AuthGate`), connect them:

```dart
final chat = context.read<ChatProvider>();
final encryption = context.read<EncryptionProvider>();
chat.setEncryptionProvider(encryption);
```

- [ ] **Step 4: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: All 61 tests PASS

- [ ] **Step 5: Manual smoke test**

Run app (`cd frontend && flutter run -d chrome`), login, verify:
- E2E encryption initializes (check console for key bundle upload)
- Messages send and decrypt correctly
- Reconnect preserves E2E state (refresh page, verify no `[Decryption failed]`)

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/main.dart frontend/lib/providers/chat_provider.dart frontend/lib/providers/encryption_provider.dart
git commit -m "refactor(frontend): wire EncryptionProvider into provider tree, ChatProvider delegates E2E state"
```

---

### Task 2.3: Move E2E initialization + key exchange logic to EncryptionProvider

**Files:**
- Modify: `frontend/lib/providers/encryption_provider.dart` (add initializeE2E, key exchange handlers)
- Modify: `frontend/lib/providers/chat_provider.dart` (remove moved methods, call EncryptionProvider)

- [ ] **Step 1: Move `_initializeE2E()` to EncryptionProvider**

Read `chat_provider.dart` to find `_initializeE2E()` (around line 1015-1100). Move it to EncryptionProvider. It needs: `_encryptionService`, `_e2eInitialized`, `_generatingMoreKeys`, and a socket emit callback for `uploadKeyBundle`/`uploadOneTimePreKeys`.

EncryptionProvider gets an `emitCallback: void Function(String event, dynamic data)` set by ConnectionProvider (or ChatProvider in facade phase).

- [ ] **Step 2: Move key exchange event handlers to EncryptionProvider**

Move handlers for:
- `onKeyBundleUploaded`
- `onOneTimePreKeysUploaded`
- `onPreKeyBundleResponse` (completes `_pendingPreKeyFetches`)
- `onPreKeysLow` (triggers replenishment)
- `onSessionRebuildNeeded` (adds to `_forceSessionRebuild`)

- [ ] **Step 3: Update ChatProvider to call EncryptionProvider for these events**

In `connect()` socket listeners, route key exchange events to `_encryptionProvider.onXxx()` instead of local handlers.

- [ ] **Step 4: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: All 61 tests PASS

- [ ] **Step 5: Manual smoke test E2E flow**

Login with 2 accounts, send messages, verify encryption works end-to-end.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/encryption_provider.dart frontend/lib/providers/chat_provider.dart
git commit -m "refactor(frontend): move E2E initialization + key exchange to EncryptionProvider"
```

---

### Phase 2 Exit Criteria Check

- [ ] EncryptionProvider extracted with clean method-based API (encrypt/decrypt/ensureSession)
- [ ] All frontend tests PASS, flutter analyze clean
- [ ] E2E encryption works in browser (manual smoke test)
- [ ] Reconnect preserves E2E state (no `[Decryption failed]`)

---

## Chunk 3: Frontend — Extract FriendsProvider (Phase 3)

Clear domain boundary. FriendsProvider owns: friend list, friend requests, block/unblock, search. Cross-domain calls to ConversationsProvider (via ChatProvider facade for now).

---

### Task 3.1: Create `FriendsProvider` skeleton with state

**Files:**
- Create: `frontend/lib/providers/friends_provider.dart`

- [ ] **Step 1: Create FriendsProvider with all friends/block state**

Move from `chat_provider.dart`:
- `_friends`, `_friendRequests`, `_pendingRequestsCount`
- `_blockedUsers`, `_blockedByUserIds`
- `_pendingFriendRequestSent` / `consumeFriendRequestSent()`
- `_pendingFriendAccepted` / `consumePendingFriendAccepted()`
- `_searchResults`

Include `onConnect(isReconnect)` / `onDisconnect()` lifecycle methods.

- [ ] **Step 2: Add event handler methods**

- `onFriendRequestsList(dynamic data)`
- `onNewFriendRequest(dynamic data)`
- `onFriendRequestSent(dynamic data)`
- `onFriendRequestAccepted(dynamic data)` — **NO getConversations/getFriends** (critical gotcha)
- `onFriendRequestRejected(dynamic data)`
- `onPendingRequestsCount(dynamic data)`
- `onFriendsList(dynamic data)`
- `onUnfriended(dynamic data)` — calls `conversationsProvider.removeConversationsForUser()`
- `onBlockedList(dynamic data)`
- `onYouWereBlocked(dynamic data)` — calls `conversationsProvider.removeConversationsForUser()`
- `onSearchUsersResult(dynamic data)`

- [ ] **Step 3: Add action methods**

- `searchUsers(String handle)`
- `sendFriendRequest(int userId)`
- `acceptFriendRequest(int requestId)`
- `rejectFriendRequest(int requestId)`
- `unfriend(int userId)`
- `blockUser(int userId)`
- `unblockUser(int userId)`
- `loadBlockedList()`

Each calls `emit()` via the socket callback.

- [ ] **Step 4: Commit skeleton**

```bash
git add frontend/lib/providers/friends_provider.dart
git commit -m "refactor(frontend): create FriendsProvider skeleton with friends/block state"
```

---

### Task 3.2: Wire FriendsProvider + migrate ChatProvider

**Files:**
- Modify: `frontend/lib/main.dart`
- Modify: `frontend/lib/providers/chat_provider.dart`

- [ ] **Step 1: Add FriendsProvider to MultiProvider**

- [ ] **Step 2: ChatProvider facade — delegate friend state to FriendsProvider**

ChatProvider keeps public getters (`friends`, `blockedUsers`, etc.) but delegates to `_friendsProvider`. Existing screens continue working via `context.read<ChatProvider>().friends`.

- [ ] **Step 3: Route friend socket events from ChatProvider.connect() to FriendsProvider**

- [ ] **Step 4: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: All 61 tests PASS

- [ ] **Step 5: Manual smoke test**

Test: send friend request, accept, reject, unfriend, block, unblock, search users. All flows should work identically.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/main.dart frontend/lib/providers/chat_provider.dart frontend/lib/providers/friends_provider.dart
git commit -m "refactor(frontend): wire FriendsProvider, ChatProvider delegates friend state"
```

---

### Phase 3 Exit Criteria Check

- [ ] FriendsProvider extracted, all friend/block flows work manually
- [ ] All frontend tests PASS, flutter analyze clean
- [ ] `onFriendRequestAccepted` does NOT call getConversations/getFriends (verified by code review)

---

## Chunk 4: Frontend — Extract ConnectionProvider + ConversationsProvider + MessagingProvider (Phase 4)

The most coupled extraction. These three are done together because they share the socket and message/conversation state.

---

### Task 4.1: Refactor SocketService to event-map pattern

**Files:**
- Modify: `frontend/lib/services/socket_service.dart`

- [ ] **Step 1: Read current socket_service.dart**

Read `frontend/lib/services/socket_service.dart` (320 lines) to understand the current 30+ callback connect signature.

- [ ] **Step 2: Refactor connect() to take only token**

Replace the 30+ named callback parameters with a simple `connect(String baseUrl, String token)`. Add an `on(String event, Function(dynamic) callback)` method that registers listeners after connect.

```dart
void connect({required String baseUrl, required String token}) {
  // ... existing socket creation logic (lines 48-65) ...
  // Remove all the on('eventName', ...) registrations from here
}

void on(String event, void Function(dynamic) callback) {
  _socket?.on(event, callback);
}

void off(String event) {
  _socket?.off(event);
}
```

Keep all emit methods unchanged (they don't depend on callbacks).

- [ ] **Step 3: Update ChatProvider.connect() to use new SocketService API**

Replace the single `_socketService.connect(onX: ..., onY: ...)` call with:
```dart
_socketService.connect(baseUrl: baseUrl, token: token);
_socketService.on('newMessage', (data) => _handleIncomingMessage(data));
_socketService.on('conversationsList', (data) => _handleConversationsList(data));
// ... etc for all ~35 events
```

- [ ] **Step 4: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: All 61 tests PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/services/socket_service.dart frontend/lib/providers/chat_provider.dart
git commit -m "refactor(frontend): SocketService event-map pattern (remove 30+ callback params)"
```

---

### Task 4.2: Create ConnectionProvider

**Files:**
- Create: `frontend/lib/providers/connection_provider.dart`

- [ ] **Step 1: Create ConnectionProvider owning socket lifecycle**

```dart
// frontend/lib/providers/connection_provider.dart
class ConnectionProvider extends ChangeNotifier {
  final SocketService _socketService = SocketService();

  int? _currentUserId;
  bool _isConnected = false;
  bool _intentionalDisconnect = false;
  late ChatReconnectManager _reconnectManager;

  // Push notification state (moved from ChatProvider)
  // PushService? _pushService;
  // bool _pushInitialized = false;

  // Sub-provider references (set after construction)
  EncryptionProvider? _encryptionProvider;
  FriendsProvider? _friendsProvider;
  ConversationsProvider? _conversationsProvider;
  MessagingProvider? _messagingProvider;

  // --- Public interface ---
  int? get currentUserId => _currentUserId;
  bool get isConnected => _isConnected;
  SocketService get socketService => _socketService;

  void setProviders({
    required EncryptionProvider encryption,
    required FriendsProvider friends,
    required ConversationsProvider conversations,
    required MessagingProvider messaging,
  }) { ... }

  void emit(String event, dynamic data) {
    _socketService.emit(event, data);
  }

  Future<void> connect(int userId, String token, String baseUrl) async {
    // 1. Cancel reconnect
    // 2. Determine isReconnect
    // 3. Call sub-providers onConnect(isReconnect)
    // 4. Create socket with enableForceNew()
    // 5. Register all listeners (routed to sub-providers)
    // 6. On 'connect': init E2E, fetch initial data
  }

  void disconnect({bool isLogout = false}) {
    // Per spec disconnect sequence
  }
}
```

- [ ] **Step 2: Commit skeleton**

```bash
git add frontend/lib/providers/connection_provider.dart
git commit -m "refactor(frontend): create ConnectionProvider skeleton"
```

---

### Task 4.3: Create ConversationsProvider

**Files:**
- Create: `frontend/lib/providers/conversations_provider.dart`

- [ ] **Step 1: Create ConversationsProvider with conversation state**

Move from `chat_provider.dart`:
- `_conversations`, `_activeConversationId`, `_unreadCounts`, `_lastMessages`
- `_pendingOpenConversationId` / `consumePendingOpen()`
- `_activeConversationDeletedByOther`
- `_error` field for error handling (per spec: each provider manages own errors)

Include inter-provider interface methods:
- `removeConversationsForUser(int userId)`
- `clearActiveIfNeeded(int userId)`
- `updateLastMessage(int conversationId, MessageModel message)`
- `updateUnreadCount(int conversationId, int count)`
- `onConnect(bool isReconnect)` / `onDisconnect()`

And event handlers:
- `onConversationsList(dynamic data)`
- `onOpenConversation(dynamic data)`
- `onConversationDeleted(dynamic data)`
- `onDisappearingTimerUpdated(dynamic data)`

**NOTE:** `conversation_helpers.dart` stays as a standalone utility file — ConversationsProvider imports it, does NOT absorb it. Screens continue importing it directly too.

- [ ] **Step 2: Commit skeleton**

```bash
git add frontend/lib/providers/conversations_provider.dart
git commit -m "refactor(frontend): create ConversationsProvider skeleton"
```

---

### Task 4.4: Create MessagingProvider

**Files:**
- Create: `frontend/lib/providers/messaging_provider.dart`

- [ ] **Step 1: Create MessagingProvider with message state**

Move from `chat_provider.dart`:
- `_messages`, `_typingUsers`, `_typingTimers`, `_partnerRecordingVoice`
- `_pendingSendContent` (explicit `<String, dynamic>` type — CLAUDE.md gotcha)
- `_replyingToMessage`, `_deletedMessageIds`
- `_decryptingHistory`, `_decryptHistoryGeneration`, `_incomingMessageQueue`
- `_delayedRetryTimer`, `_delayedRetryTempId`
- `_showPingEffect`

Include:
- `onConnect(bool isReconnect)` / `onDisconnect()`
  - `onConnect(false)`: clear all message state + clear `_incomingMessageQueue` (fresh connect = no buffered messages to preserve)
  - `onConnect(true)`: preserve messages (no flicker), preserve `_incomingMessageQueue` (may have buffered messages during reconnect)
  - `onDisconnect()`: cancel `_delayedRetryTimer`, clear typing timers
- `_error` field for error handling (per spec: each provider manages own errors)
- `clearMessagesForConversation(int? conversationId)` (inter-provider interface)
- All message event handlers:
  - `onNewMessage`, `onMessageSent`, `onMessageHistory`
  - `onMessageDelivered`, `onMessageDeleted`
  - `onChatHistoryCleared` — clears messages for conversation, calls `conversationsProvider.updateLastMessage(convId, null)` to update conversation tile
  - `onReactionUpdated`, `onLinkPreviewReady`
  - `onPartnerTyping`, `onPartnerRecordingVoice`
- Send methods (sendMessage, sendPing, sendImage, sendVoice, sendGif, sendFile)
- `_encryptAndSend()` (lives here, calls `encryptionProvider.encrypt()` — method call, not raw service access)
- `_decryptMessageHistory()` (lives here, owns queue + generation counter; calls `encryptionProvider.decrypt()` per message, `encryptionProvider.getCachedDecryption()` for cache-first)

- [ ] **Step 2: Commit skeleton**

```bash
git add frontend/lib/providers/messaging_provider.dart
git commit -m "refactor(frontend): create MessagingProvider skeleton"
```

---

### Task 4.5: Wire all providers together (ChatProvider stays as facade)

**Files:**
- Modify: `frontend/lib/main.dart` (final provider tree)
- Modify: `frontend/lib/providers/chat_provider.dart` (delegate remaining state to new providers)

- [ ] **Step 1: Update main.dart with full provider tree using ChangeNotifierProxyProvider**

Use ProxyProvider to guarantee initialization order (per spec Section 5):

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ChangeNotifierProvider(create: (_) => ConnectionProvider()),
    ChangeNotifierProxyProvider<ConnectionProvider, EncryptionProvider>(
      create: (_) => EncryptionProvider(),
      update: (_, conn, enc) => enc!..updateConnection(conn),
    ),
    ChangeNotifierProxyProvider<ConnectionProvider, ConversationsProvider>(
      create: (_) => ConversationsProvider(),
      update: (_, conn, conv) => conv!..updateConnection(conn),
    ),
    ChangeNotifierProxyProvider<ConnectionProvider, FriendsProvider>(
      create: (_) => FriendsProvider(),
      update: (_, conn, friends) => friends!..updateConnection(conn),
    ),
    ChangeNotifierProxyProvider2<ConnectionProvider, EncryptionProvider, MessagingProvider>(
      create: (_) => MessagingProvider(),
      update: (_, conn, enc, msg) => msg!..updateDependencies(conn, enc),
    ),
  ],
)
// Order: ConnectionProvider first, then Encryption, Conversations, Friends, then Messaging
// MessagingProvider depends on Connection + Encryption (ProxyProvider2)
// FriendsProvider needs ConversationsProvider + MessagingProvider for cross-domain calls (unfriend/block)
// These are set via FriendsProvider.setCrossProviders(conversations, messaging) called in ConnectionProvider.setProviders()
```

Each sub-provider has an `updateConnection(ConnectionProvider conn)` method that stores the reference (no notifyListeners — just saves the ref). MessagingProvider has `updateDependencies(ConnectionProvider conn, EncryptionProvider enc)`.

**IMPORTANT — Cascade prevention:** ProxyProvider's `update` fires when ConnectionProvider notifies. Sub-providers must NOT call `notifyListeners()` inside `updateConnection/updateDependencies` — they only save the reference. They notify only when their own state changes (per spec).

- [ ] **Step 2: Verify ChatProvider facade delegates all state to new providers**

ChatProvider keeps its public API (getters, methods) but every field and method internally calls the appropriate sub-provider. Existing `context.read<ChatProvider>()` calls in screens still work.

- [ ] **Step 3: Run frontend tests + flutter analyze**

Run: `cd frontend && flutter analyze && flutter test`
Expected: All 61 tests PASS, no analyzer errors

- [ ] **Step 4: Manual smoke test — all 5 providers wired correctly**

Test: login, send message, friend request, block/unblock, reconnect. All should work via the ChatProvider facade.

- [ ] **Step 5: Commit**

```bash
git add -A frontend/lib/
git commit -m "refactor(frontend): wire 5 providers with ProxyProvider, ChatProvider as facade"
```

---

### Task 4.6: Migrate screen/widget references + remove ChatProvider

This is the final migration — replace all `context.read<ChatProvider>()` with the appropriate new provider, then delete ChatProvider.

**Files:**
- Modify: All screens and widgets that use `context.read/watch<ChatProvider>()`
- Delete: `frontend/lib/providers/chat_provider.dart`

- [ ] **Step 1: Update all screen `context.read<ChatProvider>()` calls**

Replace with the appropriate provider:
- `ChatProvider.conversations` → `context.read<ConversationsProvider>().conversations`
- `ChatProvider.messages` → `context.read<MessagingProvider>().messages`
- `ChatProvider.friends` → `context.read<FriendsProvider>().friends`
- `ChatProvider.sendMessage(...)` → `context.read<MessagingProvider>().sendMessage(...)`
- `ChatProvider.connect(...)` → `context.read<ConnectionProvider>().connect(...)`
- etc.

Key screens to update:
- `screens/main_shell_screen.dart` — consumePendingFriendAccepted (FriendsProvider), connect (ConnectionProvider)
- `screens/conversations_screen.dart` — conversations, consumePendingOpen, unreadCounts (ConversationsProvider)
- `screens/chat_detail_screen.dart` — messages, sendMessage, markConversationRead, typing (MessagingProvider)
- `screens/contacts_screen.dart` — friends, startConversation, unfriend (FriendsProvider)
- `screens/add_or_invitations_screen.dart` — searchUsers, sendFriendRequest, consumeFriendRequestSent (FriendsProvider)
- `screens/settings_screen.dart` — disconnect (ConnectionProvider), deleteAccount
- `screens/privacy_safety_screen.dart` — blockedUsers (FriendsProvider), encryption info (EncryptionProvider)
- `screens/auth_screen.dart` — clearStatus (AuthProvider, unchanged)

- [ ] **Step 2: Update widget `context.read/watch` calls**

- `widgets/chat_input_bar.dart` → MessagingProvider (sendMessage, sendPing, sendImage, etc.)
- `widgets/chat_message_bubble.dart` → MessagingProvider (addReaction, removeReaction, deleteMessage)
- `widgets/conversation_tile.dart` → ConversationsProvider (unreadCounts)
- `widgets/chat_action_tiles.dart` → MessagingProvider + ConversationsProvider

- [ ] **Step 3: Run flutter analyze — verify zero ChatProvider references remain**

Run: `cd frontend && flutter analyze`
Run: `grep -r "ChatProvider" frontend/lib/ --include="*.dart" -l`
Expected: No files reference ChatProvider (except maybe tests — update those too)

- [ ] **Step 4: Delete old chat_provider.dart**

```bash
git rm frontend/lib/providers/chat_provider.dart
```

- [ ] **Step 5: Run frontend tests**

Run: `cd frontend && flutter test`
Expected: All 61 tests PASS (update test imports as needed)

- [ ] **Step 6: Run flutter analyze**

Run: `cd frontend && flutter analyze`
Expected: No errors. Fix any unused imports or missing references.

- [ ] **Step 7: Full manual smoke test**

Test all major flows:
- Login/logout
- Send/receive text, image, voice, GIF, file, ping
- Friend request (send, accept, reject)
- Block/unblock
- Delete conversation, clear history, delete message (for me / for everyone)
- Disappearing messages
- Typing indicators
- Reconnect (disconnect wifi, reconnect — UI must NOT flicker)
- E2E encryption (2 accounts, messages decrypt correctly)

- [ ] **Step 8: Commit**

```bash
git add -A frontend/lib/
git commit -m "refactor(frontend): phase 4 complete — all screens migrated, ChatProvider removed"
```

---

### Phase 4 Exit Criteria Check

- [ ] All 5 providers wired via ChangeNotifierProxyProvider
- [ ] Old ChatProvider deleted, zero references remain
- [ ] All 61 frontend tests PASS, flutter analyze clean
- [ ] Full manual smoke test — all features work

---

## Chunk 5: Frontend — Widget Decomposition (Phase 5)

Low risk — providers are stable, this is purely UI refactoring. Each widget split is independent.

---

### Task 5.1: Decompose `chat_message_bubble.dart` into composition pattern

**Files:**
- Create: `frontend/lib/widgets/message/` directory
- Create: `frontend/lib/widgets/message/message_content_factory.dart`
- Create: `frontend/lib/widgets/message/text_message_content.dart`
- Create: `frontend/lib/widgets/message/image_message_content.dart`
- Create: `frontend/lib/widgets/message/gif_message_content.dart`
- Create: `frontend/lib/widgets/message/file_message_content.dart`
- Create: `frontend/lib/widgets/message/ping_message_content.dart`
- Create: `frontend/lib/widgets/message/message_metadata_row.dart`
- Modify: `frontend/lib/widgets/chat_message_bubble.dart` (gut to wrapper only)
- Move: `frontend/lib/widgets/chat_message_bubble.dart` → `frontend/lib/widgets/message/chat_message_bubble.dart`

- [ ] **Step 1: Create `message_metadata_row.dart`**

Extract `_buildTimeDeliveryTimerRow()` (lines 361-390) and `_buildDeliveryIcon()` (lines 329-360) into a shared widget. This is used by ALL message types.

```dart
class MessageMetadataRow extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final int? expirySecondsLeft;
  // ...
}
```

- [ ] **Step 2: Create `message_content_factory.dart`**

```dart
class MessageContentFactory {
  static Widget build(MessageModel message, {required double maxWidth, ...}) {
    switch (message.messageType) {
      case MessageType.TEXT: return TextMessageContent(...);
      case MessageType.IMAGE: return ImageMessageContent(...);
      case MessageType.GIF: return GifMessageContent(...);
      case MessageType.VOICE: return VoiceMessageContent(...);
      case MessageType.FILE: return FileMessageContent(...);
      case MessageType.PING: return PingMessageContent(...);
    }
  }
}
```

- [ ] **Step 3: Create per-type content widgets**

Extract from `_buildContentColumn()` (lines 134-328):
- `text_message_content.dart` — lines 149-153 + `_buildTextWithLinks()` (618-670) + `_buildLinkPreviewCard()` (671-755)
- `image_message_content.dart` — lines 171-216 + `_showMediaFullscreenDialog()` (391-407)
- `gif_message_content.dart` — lines 217-237 + fullscreen dialog
- `file_message_content.dart` — lines 245-327 + download logic
- `ping_message_content.dart` — lines 154-170

Each receives `MessageModel` + theme + maxWidth. Pure rendering, no provider access.

- [ ] **Step 4: Refactor `chat_message_bubble.dart` to wrapper**

Keep only: alignment, gesture detector (long-press for reactions, swipe for reply), reply quote, content factory call, metadata row, reactions overlay.

Move to `widgets/message/chat_message_bubble.dart`.

- [ ] **Step 5: Update imports in `chat_detail_screen.dart`**

Change import path from `widgets/chat_message_bubble.dart` to `widgets/message/chat_message_bubble.dart`.

- [ ] **Step 6: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: No errors, all tests PASS

- [ ] **Step 7: Verify UI is visually identical**

Run app, check all message types render correctly (text, image, GIF, voice, file, ping, with reactions, with replies, with link previews).

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/widgets/message/ frontend/lib/screens/chat_detail_screen.dart
git rm frontend/lib/widgets/chat_message_bubble.dart
git commit -m "refactor(frontend): decompose chat_message_bubble into composition pattern"
```

---

### Task 5.2: Decompose `chat_input_bar.dart`

**Files:**
- Create: `frontend/lib/widgets/input/` directory
- Create: `frontend/lib/widgets/input/recording_controller.dart`
- Create: `frontend/lib/widgets/input/attachment_handler.dart`
- Create: `frontend/lib/widgets/input/reply_preview_bar.dart`
- Modify/Move: `frontend/lib/widgets/chat_input_bar.dart` → `frontend/lib/widgets/input/chat_input_bar.dart`

- [ ] **Step 1: Create `reply_preview_bar.dart`**

Extract `_buildReplyPreview()` (lines 458-515) into its own widget.

- [ ] **Step 2: Create `recording_controller.dart`**

**CLAUDE.md gotcha:** "Voice recording: mic must stay in widget tree — GestureDetector unmounts -> no events." The recording controller must be a StatefulWidget (not a standalone controller class) to stay in the widget tree during recording.

Extract voice recording state and logic (lines 39-58 fields, lines 161-244 start, lines 247-326 stop, lines 401-422 drag). This is a StatefulWidget that owns:
- `isRecording`, `isSendingVoice`, `audioRecorder`, `recordingStartTime`, `recordingPath`
- `showTrashIcon`, `canceledBySlide`, `pulseController`
- `countdownTickNotifier` (moved from ChatProvider per spec)

- [ ] **Step 3: Create `attachment_handler.dart`**

Extract image/file picking and upload logic. This is a utility class with methods:
- `pickAndSendImage(BuildContext context)`
- `pickAndSendFile(BuildContext context)`
- `pickAndSendGif(BuildContext context)` (opens GIF picker sheet)

- [ ] **Step 4: Slim down `chat_input_bar.dart`**

Keep: text field, send button, orchestration (calls recording controller, attachment handler, reply preview). Move to `widgets/input/`.

- [ ] **Step 5: Update imports in `chat_detail_screen.dart`**

- [ ] **Step 6: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: No errors, all tests PASS

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/widgets/input/ frontend/lib/screens/chat_detail_screen.dart
git rm frontend/lib/widgets/chat_input_bar.dart
git commit -m "refactor(frontend): decompose chat_input_bar into input/ components"
```

---

### Task 5.3: Decompose `voice_message_bubble.dart`

**Files:**
- Create: `frontend/lib/widgets/audio/` directory
- Create: `frontend/lib/widgets/audio/playback_controller.dart`
- Create: `frontend/lib/widgets/audio/waveform_display.dart`
- Create: `frontend/lib/widgets/message/voice_message_content.dart`
- Delete: `frontend/lib/widgets/voice_message_bubble.dart`

- [ ] **Step 1: Create `playback_controller.dart`**

Extract audio playback logic: `AudioPlayer` lifecycle, position/duration streams, `_loadAndPlayAudio`, `_togglePlayPause`, `_toggleSpeed`, caching (web vs native), `_downloadAndCache`.

This is a reusable controller (either a mixin or a separate class with `dispose()`).

- [ ] **Step 2: Create `waveform_display.dart`**

Extract `_WaveformPainter` (lines 554-614) and the waveform gesture detector + seek logic into a standalone widget.

- [ ] **Step 3: Create `voice_message_content.dart`**

Thin widget that composes: playback controller + waveform display + play/pause button + speed button + duration text. Lives in `widgets/message/` alongside other content types.

- [ ] **Step 4: Update message_content_factory to use voice_message_content**

In the factory, `case MessageType.VOICE` returns `VoiceMessageContent(...)`.

- [ ] **Step 5: Delete old `voice_message_bubble.dart`**

- [ ] **Step 6: Update all imports**

`chat_message_bubble.dart` and `chat_detail_screen.dart` may import voice_message_bubble — update.

- [ ] **Step 7: Run flutter analyze + tests**

Run: `cd frontend && flutter analyze && flutter test`
Expected: No errors, all tests PASS

- [ ] **Step 8: Verify voice playback works**

Manual test: send voice message, play back, scrub waveform, change speed (1x/1.5x/2x), verify caching works.

- [ ] **Step 9: Commit**

```bash
git add frontend/lib/widgets/audio/ frontend/lib/widgets/message/voice_message_content.dart frontend/lib/widgets/message/message_content_factory.dart
git rm frontend/lib/widgets/voice_message_bubble.dart
git commit -m "refactor(frontend): decompose voice_message_bubble into audio/ + voice_message_content"
```

---

## Chunk 6: Final Cleanup + CLAUDE.md Update (Phase 6)

---

### Task 6.1: Line count verification

- [ ] **Step 1: Verify no file exceeds 500 LOC**

Run: `find frontend/lib -name "*.dart" -exec wc -l {} + | sort -rn | head -20`
Expected: No file >500 lines

Run: `find backend/src -name "*.ts" ! -name "*.spec.ts" -exec wc -l {} + | sort -rn | head -20`
Expected: No file >500 lines (except `messages.service.ts` at ~428, acceptable)

- [ ] **Step 2: Verify gateway is thin**

Run: `wc -l backend/src/chat/chat.gateway.ts`
Expected: ~150-180 lines

---

### Task 6.2: Run all tests

- [ ] **Step 1: Backend tests**

Run: `cd backend && npm test`
Expected: All 152+ tests PASS

- [ ] **Step 2: Frontend tests**

Run: `cd frontend && flutter test`
Expected: All 61+ tests PASS

- [ ] **Step 3: Flutter analyze**

Run: `cd frontend && flutter analyze`
Expected: No errors

---

### Task 6.3: Update CLAUDE.md

- [ ] **Step 1: Update File Location Map (Section 3)**

Add new files to the table:
- Providers: connection_provider, conversations_provider, messaging_provider, friends_provider, encryption_provider
- Widgets: message/, input/, audio/ subdirectories
- Backend services: chat-presence, chat-block, chat-search, chat-reaction, chat-link-preview

- [ ] **Step 2: Update Architecture Overview (Section 2)**

Update state management description: "5 providers (ChangeNotifier): ConnectionProvider, ConversationsProvider, MessagingProvider, FriendsProvider, EncryptionProvider + AuthProvider, SettingsProvider"

- [ ] **Step 3: Update Known Limitations (Section 11)**

Remove "Large files: chat_provider.dart (~1970 lines)" — no longer applicable.

- [ ] **Step 4: Commit CLAUDE.md**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with refactored architecture"
```

---

### Task 6.4: Final comprehensive smoke test

- [ ] **Step 1: Full manual regression test**

Test ALL features listed in CLAUDE.md Section 8:
- [ ] Login/register/logout
- [ ] Send text message (E2E encrypted)
- [ ] Send image message
- [ ] Send voice message (hold-to-record, playback, speed, scrub)
- [ ] Send GIF message
- [ ] Send file/document
- [ ] Send ping
- [ ] Friend request (send, accept, reject, auto-accept)
- [ ] Unfriend
- [ ] Block/unblock
- [ ] Delete conversation (swipe)
- [ ] Clear chat history
- [ ] Delete message (for me / for everyone)
- [ ] Reactions (add, remove)
- [ ] Typing indicator
- [ ] Link preview
- [ ] Disappearing messages timer
- [ ] Reconnect (disconnect wifi, reconnect — UI should not flicker)
- [ ] Theme switching (light/dark/blue)
- [ ] Language switching (PL/EN)
- [ ] Unread badge count

- [ ] **Step 2: Fix any regressions found**

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "refactor: full domain-driven decomposition complete"
```
