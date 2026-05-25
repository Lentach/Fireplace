# Security Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all verifiable findings from the 2026-03-25 full security audit across backend (SSRF, WS throttling, upload limits, DB index, JWT validation) and frontend (a11y, _pendingSendContent leak), and add the missing test coverage.

**Architecture:** 12 independent, focused changes — no architectural rewrites (Redis migration, god-class split, refresh-token OAuth are explicitly out of scope). Each task is self-contained and commit-able on its own.

**Tech Stack:** NestJS 11, TypeORM, class-validator, Socket.IO 4, Flutter 3.x, Jest, flutter_test

**Branch:** `fix/security-audit-2026-03-25`

---

## Files Modified

| File | Change |
|---|---|
| `backend/src/chat/services/link-preview.service.ts` | Add 169.254.x and fe80: to PRIVATE_IP_RE |
| `backend/src/chat/services/link-preview.service.spec.ts` | Add SSRF gap tests |
| `backend/src/chat/chat.gateway.ts` | Add @UseGuards + @Throttle to 10 unguarded destructive events |
| `backend/src/chat/guards/ws-throttler.guard.spec.ts` | New: WsThrottlerGuard unit tests |
| `backend/src/config/env.validation.ts` | Add MinLength(32) to JWT_SECRET |
| `backend/src/media/media.controller.ts` | Raise upload limit to 21 MB |
| `backend/src/media/dto/upload-media.dto.ts` | Add MaxLength + path-char constraint on fileName |
| `backend/src/messages/message.entity.ts` | Add composite index on (conversation_id, createdAt) |
| `backend/src/users/users.service.spec.ts` | Add account-deletion cascade test |
| `frontend/lib/widgets/message/reaction_chips_row.dart` | Wrap chips in Semantics |
| `frontend/lib/providers/messaging_provider.dart` | Clear _pendingSendContent on reconnect |

---

## Task 1 — Fix SSRF: add missing IP ranges to PRIVATE_IP_RE

**Files:**
- Modify: `backend/src/chat/services/link-preview.service.ts:3-4`

**Context:** The current regex blocks RFC-1918 and loopback but misses `169.254.x.x` (IPv4 link-local / GCP+AWS IMDS) and `fe80::` (IPv6 link-local). This app runs on Google Cloud where `169.254.169.254` is the IMDS endpoint.

- [ ] **Step 1: Change the PRIVATE_IP_RE in link-preview.service.ts**

Replace line 3-4:
```ts
const PRIVATE_IP_RE =
  /^(localhost|127\.|10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|::1|fc00:|fd)/i;
```
with:
```ts
const PRIVATE_IP_RE =
  /^(localhost|127\.|10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|169\.254\.|::1|fc00:|fd|fe80:)/i;
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/chat/services/link-preview.service.ts
git commit -m "fix(ssrf): block 169.254.x and fe80: in link-preview PRIVATE_IP_RE"
```

---

## Task 2 — Test: verify SSRF coverage in link-preview.service.spec.ts

**Files:**
- Modify: `backend/src/chat/services/link-preview.service.spec.ts`

**Context:** There is a `LinkPreviewService.spec.ts` at `backend/src/chat/services/link-preview.service.spec.ts` but it only tests `ChatLinkPreviewService` (the wrapper). The `LinkPreviewService` (the inner service doing the actual HTTP fetch) lives at `backend/src/chat/services/link-preview.service.ts`. We need to test `isPrivateOrLocal` and `isSafeImageUrl` — these are unexported private functions, so we test them indirectly via `fetchPreview` by mocking `fetch`.

Add a new describe block at the bottom of `backend/src/chat/services/link-preview.service.spec.ts`. First read the file — the current content tests `ChatLinkPreviewService`. We add a **separate spec file** instead to avoid confusion:

- [ ] **Step 1: Create `backend/src/chat/services/link-preview.service.unit.spec.ts`**

```ts
import { LinkPreviewService } from './link-preview.service';

// We test the SSRF-blocking behaviour by mocking the global fetch.
// fetchPreview returns null for blocked IPs without ever calling fetch.
describe('LinkPreviewService – SSRF blocking', () => {
  let service: LinkPreviewService;

  beforeEach(() => {
    service = new LinkPreviewService();
    // Spy on global fetch; if it is called the test fails (blocked URLs must not reach network)
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      headers: { get: () => null },
      body: null,
    } as unknown as Response);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const blocked = [
    'http://169.254.169.254/latest/meta-data/',            // AWS IMDS
    'http://169.254.169.254/computeMetadata/v1/',          // GCP IMDS
    'http://169.254.0.1/',                                 // IPv4 link-local
    'http://[fe80::1]/',                                   // IPv6 link-local
    'http://[fc00::1]/',                                   // IPv6 ULA
    'http://10.0.0.1/',                                    // RFC-1918
    'http://192.168.1.1/',                                 // RFC-1918
    'http://127.0.0.1/',                                   // loopback
    'http://localhost/',                                   // loopback
    'http://172.16.0.1/',                                  // RFC-1918
  ];

  test.each(blocked)('blocks %s', async (url) => {
    const result = await service.fetchPreview(url);
    expect(result).toBeNull();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('allows a public HTTPS URL', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      headers: { get: (h: string) => (h === 'content-type' ? 'text/html' : null) },
      body: {
        getReader: () => ({
          read: jest
            .fn()
            .mockResolvedValueOnce({
              done: false,
              value: new TextEncoder().encode(
                '<html><head><title>Example</title></head></html>',
              ),
            })
            .mockResolvedValueOnce({ done: true, value: undefined }),
          cancel: jest.fn(),
        }),
      },
    } as unknown as Response);

    const result = await service.fetchPreview('check out https://example.com');
    expect(result?.url).toBe('https://example.com');
    expect(global.fetch).toHaveBeenCalledWith(
      'https://example.com',
      expect.objectContaining({ signal: expect.any(AbortSignal) }),
    );
  });
});
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
cd backend && npm test -- --testPathPattern="link-preview.service.unit" --no-coverage
```

Expected: 11 tests pass.

- [ ] **Step 3: Commit**

```bash
git add backend/src/chat/services/link-preview.service.unit.spec.ts
git commit -m "test(ssrf): verify 169.254/fe80 blocking in LinkPreviewService"
```

---

## Task 3 — Add WS throttle guards to destructive events

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts`

**Context:** Events without `@UseGuards(WsThrottlerGuard)` are not rate-limited at all (the global ThrottlerModule covers HTTP only). The highest-risk unguarded events are: `clearChatHistory`, `deleteMessage`, `addReaction`, `removeReaction`, `uploadOneTimePreKeys`, `requestSessionRebuild`, `startConversation`, `deleteConversationOnly`, `setDisappearingTimer`, `sendFriendRequest`, `unfriend`, `blockUser`.

Limits chosen: destructive mutations get 60/15min; social actions 30/15min; key operations 10/15min.

- [ ] **Step 1: Add throttle to `clearChatHistory` (line ~171)**

Replace:
```ts
  @SubscribeMessage('clearChatHistory')
  handleClearChatHistory(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('clearChatHistory')
  handleClearChatHistory(
```

- [ ] **Step 2: Add throttle to `deleteMessage` (line ~184)**

Replace:
```ts
  @SubscribeMessage('deleteMessage')
  handleDeleteMessage(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('deleteMessage')
  handleDeleteMessage(
```

- [ ] **Step 3: Add throttle to `addReaction` and `removeReaction` (lines ~207, ~215)**

Replace:
```ts
  @SubscribeMessage('addReaction')
  async handleAddReaction(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 120, ttl: 900000 } })
  @SubscribeMessage('addReaction')
  async handleAddReaction(
```

Replace:
```ts
  @SubscribeMessage('removeReaction')
  async handleRemoveReaction(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 120, ttl: 900000 } })
  @SubscribeMessage('removeReaction')
  async handleRemoveReaction(
```

- [ ] **Step 4: Add throttle to `uploadOneTimePreKeys` (line ~241)**

Replace:
```ts
  @SubscribeMessage('uploadOneTimePreKeys')
  async handleUploadOneTimePreKeys(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 900000 } })
  @SubscribeMessage('uploadOneTimePreKeys')
  async handleUploadOneTimePreKeys(
```

- [ ] **Step 5: Add throttle to `requestSessionRebuild` (line ~263)**

Replace:
```ts
  @SubscribeMessage('requestSessionRebuild')
  async handleRequestSessionRebuild(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
  @SubscribeMessage('requestSessionRebuild')
  async handleRequestSessionRebuild(
```

- [ ] **Step 6: Add throttle to `startConversation` (line ~278)**

Replace:
```ts
  @SubscribeMessage('startConversation')
  async handleStartConversation(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('startConversation')
  async handleStartConversation(
```

- [ ] **Step 7: Add throttle to `deleteConversationOnly` (line ~298)**

Replace:
```ts
  @SubscribeMessage('deleteConversationOnly')
  async handleDeleteConversationOnly(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('deleteConversationOnly')
  async handleDeleteConversationOnly(
```

- [ ] **Step 8: Add throttle to `sendFriendRequest` (line ~336)**

Replace:
```ts
  @SubscribeMessage('sendFriendRequest')
  async handleSendFriendRequest(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
  @SubscribeMessage('sendFriendRequest')
  async handleSendFriendRequest(
```

- [ ] **Step 9: Add throttle to `unfriend` (line ~387)**

Replace:
```ts
  @SubscribeMessage('unfriend')
  async handleUnfriend(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
  @SubscribeMessage('unfriend')
  async handleUnfriend(
```

- [ ] **Step 10: Add throttle to `blockUser` (line ~400)**

Replace:
```ts
  @SubscribeMessage('blockUser')
  async handleBlockUser(
```
with:
```ts
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
  @SubscribeMessage('blockUser')
  async handleBlockUser(
```

- [ ] **Step 11: Run backend tests to confirm no regressions**

```bash
cd backend && npm test -- --no-coverage
```

Expected: all existing tests pass (throttle guards don't affect unit tests because guards are tested separately).

- [ ] **Step 12: Commit**

```bash
git add backend/src/chat/chat.gateway.ts
git commit -m "fix(ws): add rate-limit guards to destructive WebSocket events"
```

---

## Task 4 — Test: WsThrottlerGuard unit test

**Files:**
- Create: `backend/src/chat/guards/ws-throttler.guard.spec.ts`

**Context:** The `WsThrottlerGuard` overrides `getRequestResponse` and `getTracker`. If a future NestJS upgrade changes the `ThrottlerGuard` interface, the mock breaks silently. This test ensures both overrides return valid values.

- [ ] **Step 1: Create the spec file**

```ts
import { ExecutionContext } from '@nestjs/common';
import { WsThrottlerGuard } from './ws-throttler.guard';

describe('WsThrottlerGuard', () => {
  let guard: WsThrottlerGuard;

  beforeEach(() => {
    // WsThrottlerGuard extends ThrottlerGuard; we only test the two overridden methods
    guard = new WsThrottlerGuard({} as any, {} as any, {} as any);
  });

  describe('getRequestResponse', () => {
    it('returns req derived from socket handshake headers', () => {
      const mockSocket = {
        handshake: { headers: { 'x-forwarded-for': '1.2.3.4' }, address: '127.0.0.1' },
        data: { user: { id: 42 } },
      };
      const context = {
        switchToWs: () => ({ getClient: () => mockSocket }),
      } as unknown as ExecutionContext;

      const { req, res } = (guard as any).getRequestResponse(context);

      // req must expose headers
      expect(req.headers).toEqual(mockSocket.handshake.headers);
      // res.header must be callable without throwing (no-op mock)
      expect(() => res.header('X-RateLimit-Limit', '100')).not.toThrow();
    });

    it('res.header() returns the res object for chaining', () => {
      const mockSocket = {
        handshake: { headers: {}, address: '127.0.0.1' },
        data: { user: { id: 1 } },
      };
      const context = {
        switchToWs: () => ({ getClient: () => mockSocket }),
      } as unknown as ExecutionContext;

      const { res } = (guard as any).getRequestResponse(context);
      const result = res.header('X-Test', 'value');
      expect(result).toBe(res);
    });
  });

  describe('getTracker', () => {
    it('returns user id string when socket.data.user is set', async () => {
      const req = { data: { user: { id: 99 } }, handshake: { address: '1.2.3.4' } };
      const tracker = await (guard as any).getTracker(req);
      expect(tracker).toBe('99');
    });

    it('falls back to handshake address when no user', async () => {
      const req = { data: {}, handshake: { address: '5.6.7.8' } };
      const tracker = await (guard as any).getTracker(req);
      expect(tracker).toBe('5.6.7.8');
    });

    it('falls back to "unknown" when neither user nor address', async () => {
      const req = { data: {}, handshake: {} };
      const tracker = await (guard as any).getTracker(req);
      expect(tracker).toBe('unknown');
    });
  });
});
```

- [ ] **Step 2: Run the new test**

```bash
cd backend && npm test -- --testPathPattern="ws-throttler.guard" --no-coverage
```

Expected: 5 tests pass.

- [ ] **Step 3: Commit**

```bash
git add backend/src/chat/guards/ws-throttler.guard.spec.ts
git commit -m "test(ws): add WsThrottlerGuard unit tests for getRequestResponse and getTracker"
```

---

## Task 5 — Enforce JWT_SECRET minimum length in env.validation.ts

**Files:**
- Modify: `backend/src/config/env.validation.ts`

**Context:** `JWT_SECRET` currently has only `@IsString()`. If it is set to a short value (< 32 chars) in production, HMAC-SHA256 security degrades. Adding `@MinLength(32)` fails startup with a clear error.

- [ ] **Step 1: Add MinLength import and decorator**

At the top import, add `MinLength` to the import list:
```ts
import {
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  MinLength,
  validateSync,
} from 'class-validator';
```

Replace the `JWT_SECRET` field (lines 38–39):
```ts
  @IsString()
  JWT_SECRET: string;
```
with:
```ts
  @IsString()
  @MinLength(32, { message: 'JWT_SECRET must be at least 32 characters' })
  JWT_SECRET: string;
```

- [ ] **Step 2: Run backend tests**

```bash
cd backend && npm test -- --no-coverage
```

Expected: all tests pass (tests use a `test-secret` mock that is 11 chars — but env.validation is only run at bootstrap, not in unit tests).

- [ ] **Step 3: Commit**

```bash
git add backend/src/config/env.validation.ts
git commit -m "fix(auth): enforce JWT_SECRET minimum length of 32 chars at startup"
```

---

## Task 6 — Fix upload size mismatch: raise server limit to 21 MB

**Files:**
- Modify: `backend/src/media/media.controller.ts:35`

**Context:** Client-side `MediaCryptoService.maxBytes = 20 MB`. AES-256-GCM adds 16 bytes overhead. Server currently rejects uploads > 11 MB, causing silent failures for 11–20 MB files that encrypt successfully on the client. Raise to `21 * 1024 * 1024` (21 MB) to match.

- [ ] **Step 1: Update fileSize limit**

Replace line 35:
```ts
    FileInterceptor('file', { limits: { fileSize: 11 * 1024 * 1024 } }),
```
with:
```ts
    FileInterceptor('file', { limits: { fileSize: 21 * 1024 * 1024 } }),
```

- [ ] **Step 2: Run backend tests**

```bash
cd backend && npm test -- --testPathPattern="media.controller" --no-coverage
```

Expected: existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add backend/src/media/media.controller.ts
git commit -m "fix(media): align server upload limit to 21MB (matches 20MB client AES limit)"
```

---

## Task 7 — Add fileName constraints in UploadMediaDto

**Files:**
- Modify: `backend/src/media/dto/upload-media.dto.ts`

**Context:** `fileName` has no length or content validation. A path-traversal-looking name like `../../../../etc/passwd` is accepted (though never used as a filesystem path). Adding `@MaxLength(255)` and a character constraint prevents the field from being used to smuggle long strings or path chars.

- [ ] **Step 1: Add Matches and MaxLength decorators**

Replace the full `upload-media.dto.ts`:
```ts
import { IsIn, IsNumber, IsOptional, IsString, MaxLength, Matches } from 'class-validator';
import { Type } from 'class-transformer';

export class UploadMediaDto {
  @IsIn(['image', 'voice', 'gif', 'file', 'avatar'])
  mediaType: 'image' | 'voice' | 'gif' | 'file' | 'avatar';

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  duration?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  expiresIn?: number;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  @Matches(/^[^/\\]+$/, { message: 'fileName must not contain path separators' })
  fileName?: string;
}
```

- [ ] **Step 2: Run backend tests**

```bash
cd backend && npm test -- --no-coverage
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add backend/src/media/dto/upload-media.dto.ts
git commit -m "fix(media): add MaxLength(255) and path-char constraint on fileName"
```

---

## Task 8 — Add DB index on messages(conversation_id, createdAt)

**Files:**
- Modify: `backend/src/messages/message.entity.ts`

**Context:** `findByConversation` orders by `createdAt DESC` filtered by `conversation_id`. Without a composite index, PostgreSQL performs a sequential scan of the entire `messages` table. `getLastMessagesBatch` also uses `ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY "createdAt" DESC)` which benefits from the same index.

- [ ] **Step 1: Add Index import and composite index decorator**

Add `Index` to the TypeORM imports at line 1–8 of `message.entity.ts`:
```ts
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
```

Add the composite index decorator just before `@Entity('messages')`:
```ts
@Index('idx_messages_conv_created', ['conversation', 'createdAt'])
@Entity('messages')
export class Message {
```

> Note: `synchronize: true` is active in development — TypeORM will create this index on next backend restart. In production the index must be applied manually: `CREATE INDEX CONCURRENTLY idx_messages_conv_created ON messages (conversation_id, "createdAt" DESC);`

- [ ] **Step 2: Run backend tests**

```bash
cd backend && npm test -- --no-coverage
```

Expected: all tests pass (index is a DDL annotation, no runtime behaviour change in tests).

- [ ] **Step 3: Commit**

```bash
git add backend/src/messages/message.entity.ts
git commit -m "perf(db): add composite index on messages(conversation_id, createdAt)"
```

---

## Task 9 — Test: account deletion cascade

**Files:**
- Modify: `backend/src/users/users.service.spec.ts` (or create `users.service.cascade.spec.ts` if the file is too large)

**Context:** `deleteAccount()` manually deletes: key bundles, OTPs, messages, conversations, friend requests, then the user. If any step silently fails, orphaned rows accumulate with no detection. This test verifies the call chain.

First check the deleteAccount signature:

```bash
grep -n "deleteAccount" backend/src/users/users.service.ts | head -20
```

The signature should be: `async deleteAccount(userId: number, password: string): Promise<void>`

- [ ] **Step 1: Create `backend/src/users/users.service.cascade.spec.ts`**

```ts
import { UsersService } from './users.service';

describe('UsersService.deleteAccount – cascade', () => {
  let service: UsersService;

  const mockUser = {
    id: 7,
    password: '$2b$10$validhashhere........................................',
  };

  const mockRepo = { findOne: jest.fn(), remove: jest.fn() };
  const mockStorage = { deleteAvatar: jest.fn() };
  const mockFcm = { removeAllForUser: jest.fn() };
  const mockKeyBundles = { deleteByUserId: jest.fn() };
  const mockMessages = { findMediaUrlsByConversation: jest.fn().mockResolvedValue([]) };
  const mockMediaCleanup = { cleanupOrphanedBlobs: jest.fn() };

  // Conversations repo reached via dataSource.transaction
  const mockConvRepo = {
    find: jest.fn().mockResolvedValue([{ id: 10 }, { id: 11 }]),
    delete: jest.fn(),
  };
  const mockFriendRepo = { find: jest.fn().mockResolvedValue([]), remove: jest.fn() };
  const mockMsgDeleteAll = jest.fn();

  const mockDataSource = {
    transaction: jest.fn().mockImplementation(async (fn: Function) =>
      fn({
        find: jest.fn()
          .mockImplementationOnce(() => Promise.resolve([{ id: 10 }, { id: 11 }]))
          .mockImplementationOnce(() => Promise.resolve([])),
        delete: jest.fn(),
        remove: jest.fn(),
      }),
    ),
    getRepository: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();

    service = new UsersService(
      mockRepo as any,
      mockStorage as any,
      mockFcm as any,
      mockKeyBundles as any,
      mockDataSource as any,
      { deleteAllByConversation: mockMsgDeleteAll, findMediaUrlsByConversation: jest.fn().mockResolvedValue([]) } as any,
      mockMediaCleanup as any,
    );
  });

  it('calls deleteByUserId on key bundles service before user removal', async () => {
    jest.spyOn(require('bcrypt'), 'compare').mockResolvedValue(true as never);
    mockRepo.findOne.mockResolvedValue(mockUser);

    await service.deleteAccount(7, 'correct-password');

    expect(mockKeyBundles.deleteByUserId).toHaveBeenCalledWith(7);
  });

  it('calls fcm removeAllForUser', async () => {
    jest.spyOn(require('bcrypt'), 'compare').mockResolvedValue(true as never);
    mockRepo.findOne.mockResolvedValue(mockUser);

    await service.deleteAccount(7, 'correct-password');

    expect(mockFcm.removeAllForUser).toHaveBeenCalledWith(7);
  });

  it('rejects with UnauthorizedException when password is wrong', async () => {
    jest.spyOn(require('bcrypt'), 'compare').mockResolvedValue(false as never);
    mockRepo.findOne.mockResolvedValue(mockUser);

    await expect(service.deleteAccount(7, 'wrong')).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Inspect the actual `deleteAccount` implementation to align mocks**

```bash
grep -n "deleteAccount\|keyBundles\|fcmTokens\|conversation\|friendRequest" backend/src/users/users.service.ts | head -40
```

Adjust mock expectations to match the actual call sequence seen in the output.

- [ ] **Step 3: Run the new tests**

```bash
cd backend && npm test -- --testPathPattern="users.service.cascade" --no-coverage
```

Expected: 3 tests pass (adjust if implementation differs from template above).

- [ ] **Step 4: Commit**

```bash
git add backend/src/users/users.service.cascade.spec.ts
git commit -m "test(users): verify deleteAccount calls key-bundle and FCM cleanup"
```

---

## Task 10 — Fix _pendingSendContent leak on reconnect

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`

**Context:** On reconnect (`onConnect(isReconnect: true)`), `_pendingSendContent` is not cleared. Any entry that accumulated from a failed send before the disconnect will persist until logout. Since `_cancelDelayedRetryIfAny()` is already called on reconnect (cancelling the retry timer), the content is effectively orphaned. Clear it on reconnect too.

The `onConnect` method lives around line 2075–2117. The reconnect branch (lines 2103–2113) must be updated.

- [ ] **Step 1: Find the reconnect branch and add the clear**

Read the reconnect branch — it starts at the `else` block around line 2103. Add `_pendingSendContent.clear();` after `_cancelDelayedRetryIfAny();`:

Replace:
```dart
    } else {
      // Reconnect (same user): keep messages to avoid flicker.
      // Clear typing/recording indicators (stale after reconnect).
      _typingStatus.clear();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      _partnerRecordingVoice.clear();
      _replyingToMessage = null;
      _cancelDelayedRetryIfAny();
    }
```
with:
```dart
    } else {
      // Reconnect (same user): keep messages to avoid flicker.
      // Clear typing/recording indicators (stale after reconnect).
      _typingStatus.clear();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      _partnerRecordingVoice.clear();
      _replyingToMessage = null;
      _pendingSendContent.clear(); // retry was cancelled; orphaned entries serve no purpose
      _cancelDelayedRetryIfAny();
    }
```

- [ ] **Step 2: Run Flutter tests**

```bash
cd frontend && flutter test test/providers/messaging_provider_test.dart test/providers/messaging_provider_cache_test.dart
```

Expected: all existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/messaging_provider.dart
git commit -m "fix(messaging): clear _pendingSendContent on reconnect to prevent stale leak"
```

---

## Task 11 — a11y: add Semantics to ReactionChipsRow

**Files:**
- Modify: `frontend/lib/widgets/message/reaction_chips_row.dart`

**Context:** The `GestureDetector` wrapping each emoji chip has no semantic label. Screen readers (TalkBack/VoiceOver) cannot announce the chip's purpose or current state.

- [ ] **Step 1: Wrap each chip GestureDetector with Semantics**

Replace the `GestureDetector` construction inside the `.map()`:
```dart
          return GestureDetector(
            onTap: () => onTap(e.key, isMine),
            child: Container(
```
with:
```dart
          return Semantics(
            label: isMine
                ? 'Remove ${e.key} reaction (${e.value.length})'
                : 'React with ${e.key} (${e.value.length})',
            button: true,
            child: GestureDetector(
              onTap: () => onTap(e.key, isMine),
              child: Container(
```

And close the extra `child` with an additional `)` after the closing of `Container`:
```dart
              ),
            ),
          );
```

The full updated `build` method:
```dart
  @override
  Widget build(BuildContext context) {
    final chips = reactions.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) {
          final isMine = e.value.contains(currentUserId);
          return Semantics(
            label: isMine
                ? 'Remove ${e.key} reaction (${e.value.length})'
                : 'React with ${e.key} (${e.value.length})',
            button: true,
            child: GestureDetector(
              onTap: () => onTap(e.key, isMine),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isMine
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMine
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                  ),
                ),
                child: Text('${e.key} ${e.value.length}', style: const TextStyle(fontSize: 12)),
              ),
            ),
          );
        }).toList();

    return Wrap(spacing: 4, runSpacing: 2, children: chips);
  }
```

- [ ] **Step 2: Run Flutter tests**

```bash
cd frontend && flutter test
```

Expected: all 79 tests pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/widgets/message/reaction_chips_row.dart
git commit -m "fix(a11y): add Semantics labels to ReactionChipsRow chips"
```

---

## Task 12 — Update CLAUDE.md with audit findings and production index note

**Files:**
- Modify: `CLAUDE.md`

**Context:** The new DB index needs a manual migration note for production. The SSRF fix and WS throttle additions should be noted.

- [ ] **Step 1: Add production index note to Section 1 (Critical Rules & Gotchas)**

Under the `### Backend` section in `CLAUDE.md`, add after the existing raw SQL note:
```
- `messages` table has composite index `idx_messages_conv_created` on `(conversation_id, createdAt DESC)` — auto-created in dev via synchronize; production requires manual: `CREATE INDEX CONCURRENTLY idx_messages_conv_created ON messages (conversation_id, "createdAt" DESC);`
- WS throttle guards: `@UseGuards(WsThrottlerGuard)` + `@Throttle(...)` must appear on ALL mutating WebSocket events — global ThrottlerModule only covers HTTP
- SSRF: `PRIVATE_IP_RE` in `link-preview.service.ts` blocks `169.254.x`, `fe80:`, RFC-1918 and loopback — verify coverage when adding new IP range exclusions
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude-md): document DB index, WS throttle rule, SSRF coverage"
```

---

## Self-Review

### Spec Coverage Check

| Finding | Task |
|---|---|
| 🟠 SSRF 169.254.x missing | Task 1 (fix) + Task 2 (test) |
| 🟠 WS events unthrottled | Task 3 (fix) + Task 4 (test) |
| 🟡 JWT_SECRET min length | Task 5 |
| 🟡 Upload 11MB vs 20MB mismatch | Task 6 |
| 🟡 fileName no constraints | Task 7 |
| 🟡 Missing DB index | Task 8 |
| 🟡 Account deletion cascade test | Task 9 |
| 🟡 _pendingSendContent leak | Task 10 |
| 🟡 a11y reaction chips | Task 11 |
| 🔵 CLAUDE.md update | Task 12 |

**Explicitly out of scope (architectural):**
- Refresh token / JWT rotation (OAuth flow overhaul)
- Redis for `onlineUsers` (infrastructure change)
- `messaging_provider.dart` god-class split (risky refactor, separate branch needed)
- `hiddenByUserId` DB-level filter (complex query rewrite, separate branch)
- New message live-region a11y (no existing test harness for SemanticsService)

### Placeholder Scan
No TBD, TODO, or "implement later" present. All code blocks are complete.

### Type Consistency
- `WsThrottlerGuard` constructor uses `(guard as any)` to access protected methods — consistent with how Jest tests access private methods across all existing specs.
- `UploadMediaDto` changes preserve the existing field names used in `media.controller.ts`.
- `Semantics` widget is from `package:flutter/material.dart` already imported.
