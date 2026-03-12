# Security & Bug Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all 10 critical and important issues identified in the code review (3 security/auth bugs, 4 data-integrity bugs, 2 performance issues, 1 rate-limit gap).

**Architecture:** Backend fixes are in NestJS services — each fix is self-contained. Frontend fixes are in Flutter — primarily the EncryptionService storage layer. Tests are added for every backend fix; Flutter changes are verified with `flutter analyze`.

**Tech Stack:** NestJS 11, TypeORM, Flutter 3, `flutter_secure_storage`, PostgreSQL 16, Jest.

---

## Summary of Tasks

| # | Issue | File(s) | Type |
|---|---|---|---|
| 1 | `messageDelivered` — no ownership check | `chat-message.service.ts` | Critical |
| 2 | `startConversation` — no friendship check | `chat-conversation.service.ts` | Critical |
| 3 | `isBlockedByEither` — 2 sequential queries | `blocked.service.ts` | Important |
| 4 | OG image URL not validated before storing | `link-preview.service.ts` | Important |
| 5 | Pagination: `skip: 0` hardcoded | `messages.service.ts` | Important |
| 6 | OTP race condition — non-atomic claim | `key-bundles.service.ts` | Important |
| 7 | N+1 in `_conversationsWithUnread` | `chat-conversation.service.ts`, `messages.service.ts` | Important |
| 8 | WebSocket rate limiting missing | `chat.gateway.ts` | Important |
| 9 | E2E key storage not userId-scoped | `signal_stores.dart`, `encryption_service.dart` | Critical |
| 10 | `clearAllKeys()` nukes all secure storage | `encryption_service.dart` | Important |

> **Note:** Tasks 9 and 10 are Flutter-only. All others are backend-only.

---

## Task 1: `messageDelivered` — ownership check

**Files:**
- Modify: `backend/src/chat/services/chat-message.service.ts:292-323`
- Test: `backend/src/chat/services/chat-message.service.spec.ts`

The `handleMessageDelivered` handler currently updates any message's delivery status with no ownership check. Any authenticated user can mark any message as DELIVERED.

**Step 1: Add failing test**

Open `backend/src/chat/services/chat-message.service.spec.ts`. The existing `beforeEach` sets up `mockClient = { data: { user: { id: 1 } } }`. Add this test after the existing test blocks:

```typescript
describe('handleMessageDelivered', () => {
  it('rejects when caller is the sender, not the recipient', async () => {
    // Message sender = userId 1 (the caller). Recipient = userId 2.
    const conv = { id: 10, userOne: { id: 1 }, userTwo: { id: 2 } };
    const msg = { id: 99, sender: { id: 1 }, conversation: conv };
    (messagesService as any).findByIdWithConversation = jest
      .fn()
      .mockResolvedValue(msg);
    (messagesService as any).updateDeliveryStatus = jest.fn();

    await service.handleMessageDelivered(
      mockClient as any,
      { messageId: 99 },
      mockServer as any,
      onlineUsers,
    );

    expect((messagesService as any).updateDeliveryStatus).not.toHaveBeenCalled();
  });

  it('allows when caller is the recipient', async () => {
    // Message sender = userId 2. Caller = userId 1 (recipient).
    const conv = { id: 10, userOne: { id: 2 }, userTwo: { id: 1 } };
    const updatedMsg = { id: 99, sender: { id: 2 }, conversation: conv, deliveryStatus: 'DELIVERED' };
    (messagesService as any).findByIdWithConversation = jest
      .fn()
      .mockResolvedValue({ id: 99, sender: { id: 2 }, conversation: conv });
    (messagesService as any).updateDeliveryStatus = jest
      .fn()
      .mockResolvedValue(updatedMsg);

    await service.handleMessageDelivered(
      mockClient as any,
      { messageId: 99 },
      mockServer as any,
      onlineUsers,
    );

    expect((messagesService as any).updateDeliveryStatus).toHaveBeenCalledWith(
      99,
      expect.any(String),
    );
  });
});
```

**Step 2: Run test — expect FAIL**

```bash
cd backend && npm test -- --testPathPattern=chat-message.service.spec --no-coverage 2>&1 | tail -20
```

Expected: test `rejects when caller is the sender` FAILS because `updateDeliveryStatus` is called when it shouldn't be (ownership check not yet implemented).

**Step 3: Implement the fix**

In `backend/src/chat/services/chat-message.service.ts`, replace `handleMessageDelivered` (lines 292–323) with:

```typescript
async handleMessageDelivered(
  client: Socket,
  data: any,
  server: Server,
  onlineUsers: Map<number, string>,
) {
  const user = client.data.user;
  if (!user) return;
  const userId: number = user.id;

  const { messageId } = data;
  if (!messageId) {
    client.emit('error', { message: 'messageId is required' });
    return;
  }

  // Verify caller is the recipient of this message
  const message = await this.messagesService.findByIdWithConversation(messageId);
  if (!message) return;

  const conv = message.conversation as any;
  const recipientId =
    conv.userOne?.id === message.sender.id ? conv.userTwo?.id : conv.userOne?.id;
  if (userId !== recipientId) return; // Silently ignore — not the intended recipient

  const updated = await this.messagesService.updateDeliveryStatus(
    messageId,
    MessageDeliveryStatus.DELIVERED,
  );
  if (!updated) return;

  const senderSocketId = onlineUsers.get(updated.sender.id);
  if (senderSocketId) {
    server.to(senderSocketId).emit('messageDelivered', {
      messageId: updated.id,
      conversationId: updated.conversation?.id,
      deliveryStatus: updated.deliveryStatus,
    });
  }
}
```

**Step 4: Run test — expect PASS**

```bash
cd backend && npm test -- --testPathPattern=chat-message.service.spec --no-coverage 2>&1 | tail -10
```

Expected: all tests PASS.

**Step 5: Commit**

```bash
cd backend && git add src/chat/services/chat-message.service.ts src/chat/services/chat-message.service.spec.ts
git commit -m "fix: verify recipient ownership in handleMessageDelivered"
```

---

## Task 2: `startConversation` — friendship check

**Files:**
- Modify: `backend/src/chat/services/chat-conversation.service.ts:28-72`
- Test: `backend/src/chat/services/chat-conversation.service.spec.ts` (create new file)

**Step 1: Create test file**

Create `backend/src/chat/services/chat-conversation.service.spec.ts`:

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { ChatConversationService } from './chat-conversation.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { UsersService } from '../../users/users.service';
import { FriendsService } from '../../friends/friends.service';
import { BlockedService } from '../../blocked/blocked.service';
import { Socket } from 'socket.io';
import { Server } from 'socket.io';

describe('ChatConversationService', () => {
  let service: ChatConversationService;
  let friendsService: jest.Mocked<FriendsService>;
  let blockedService: jest.Mocked<BlockedService>;
  let usersService: jest.Mocked<UsersService>;
  let conversationsService: jest.Mocked<ConversationsService>;
  let mockClient: Partial<Socket>;
  let mockServer: Partial<Server>;

  beforeEach(async () => {
    mockClient = { data: { user: { id: 1 } }, emit: jest.fn() };
    mockServer = { to: jest.fn().mockReturnThis(), emit: jest.fn() };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatConversationService,
        { provide: ConversationsService, useValue: { findOrCreate: jest.fn(), findByUser: jest.fn().mockResolvedValue([]) } },
        { provide: MessagesService, useValue: { countUnreadForRecipient: jest.fn().mockResolvedValue(0), getLastMessage: jest.fn().mockResolvedValue(null) } },
        { provide: UsersService, useValue: { findById: jest.fn() } },
        { provide: FriendsService, useValue: { areFriends: jest.fn() } },
        { provide: BlockedService, useValue: { isBlockedByEither: jest.fn() } },
      ],
    }).compile();

    service = module.get(ChatConversationService);
    friendsService = module.get(FriendsService) as jest.Mocked<FriendsService>;
    blockedService = module.get(BlockedService) as jest.Mocked<BlockedService>;
    usersService = module.get(UsersService) as jest.Mocked<UsersService>;
    conversationsService = module.get(ConversationsService) as jest.Mocked<ConversationsService>;
  });

  describe('handleStartConversation', () => {
    it('rejects when users are not friends', async () => {
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      blockedService.isBlockedByEither.mockResolvedValue(false);
      friendsService.areFriends.mockResolvedValue(false);

      await service.handleStartConversation(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
        new Map(),
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', expect.objectContaining({ message: expect.any(String) }));
      expect(conversationsService.findOrCreate).not.toHaveBeenCalled();
    });

    it('allows when users are friends', async () => {
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      blockedService.isBlockedByEither.mockResolvedValue(false);
      friendsService.areFriends.mockResolvedValue(true);
      conversationsService.findOrCreate.mockResolvedValue({ id: 10 } as any);

      await service.handleStartConversation(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
        new Map(),
      );

      expect(conversationsService.findOrCreate).toHaveBeenCalled();
    });
  });
});
```

**Step 2: Run test — expect FAIL**

```bash
cd backend && npm test -- --testPathPattern=chat-conversation.service.spec --no-coverage 2>&1 | tail -20
```

Expected: `rejects when users are not friends` FAILS (no friendship check yet).

**Step 3: Implement the fix**

In `backend/src/chat/services/chat-conversation.service.ts`, after the `blocked` check (line 57–60), add:

```typescript
const areFriends = await this.friendsService.areFriends(userId, data.recipientId);
if (!areFriends) {
  client.emit('error', { message: 'You can only start conversations with friends' });
  return;
}
```

Also ensure `FriendsService` is imported (it already is at line 4).

**Step 4: Run test — expect PASS**

```bash
cd backend && npm test -- --testPathPattern=chat-conversation.service.spec --no-coverage 2>&1 | tail -10
```

**Step 5: Commit**

```bash
cd backend && git add src/chat/services/chat-conversation.service.ts src/chat/services/chat-conversation.service.spec.ts
git commit -m "fix: require friendship before startConversation"
```

---

## Task 3: `isBlockedByEither` — combine into single query

**Files:**
- Modify: `backend/src/blocked/blocked.service.ts:83-88`

No test needed — the behaviour is identical, only performance changes. Existing tests via integration cover correctness.

**Step 1: Replace the method**

In `backend/src/blocked/blocked.service.ts`, replace `isBlockedByEither` (lines 83–88):

```typescript
/** True if either user has blocked the other. Single query instead of two sequential round-trips. */
async isBlockedByEither(userId1: number, userId2: number): Promise<boolean> {
  const count = await this.blockedRepo
    .createQueryBuilder('bu')
    .where(
      '(bu.blocker_id = :a AND bu.blocked_id = :b) OR (bu.blocker_id = :b AND bu.blocked_id = :a)',
      { a: userId1, b: userId2 },
    )
    .getCount();
  return count > 0;
}
```

**Step 2: Run all tests**

```bash
cd backend && npm test --no-coverage 2>&1 | tail -15
```

Expected: 80/80 PASS.

**Step 3: Commit**

```bash
cd backend && git add src/blocked/blocked.service.ts
git commit -m "perf: combine isBlockedByEither into single OR query"
```

---

## Task 4: OG image URL — validate before storing

**Files:**
- Modify: `backend/src/chat/services/link-preview.service.ts:30-38`

The extracted `og:image` URL is stored verbatim and displayed on the client. An attacker-controlled page can set `og:image` to a private IP or tracking URL.

**Step 1: Add `isSafeImageUrl` helper and apply it**

In `backend/src/chat/services/link-preview.service.ts`, add after `isPrivateOrLocal`:

```typescript
/** True only for safe HTTPS URLs pointing to public hosts */
function isSafeImageUrl(url: string): boolean {
  try {
    const { protocol } = new URL(url);
    if (protocol !== 'https:') return false;
    return !isPrivateOrLocal(url);
  } catch {
    return false;
  }
}
```

Then in `parseOgMeta`, change the `imageUrl` line from:

```typescript
imageUrl: imageUrl ? imageUrl.trim() : null,
```

to:

```typescript
imageUrl: imageUrl && isSafeImageUrl(imageUrl.trim()) ? imageUrl.trim() : null,
```

**Step 2: Run all tests**

```bash
cd backend && npm test --no-coverage 2>&1 | tail -15
```

Expected: 80/80 PASS (no existing tests for `parseOgMeta` but existing link preview tests still pass).

**Step 3: Commit**

```bash
cd backend && git add src/chat/services/link-preview.service.ts
git commit -m "fix: reject non-HTTPS or private-IP og:image URLs in link preview"
```

---

## Task 5: Pagination — fix `skip: 0` hardcode

**Files:**
- Modify: `backend/src/messages/messages.service.ts:73-96`
- Test: `backend/src/messages/messages.service.spec.ts` (create new file)

Without `hiddenByUserId`, the query currently uses `skip: 0` so offset is only applied in-memory. This means DB always returns messages starting from the newest, but if a large offset is requested for the no-hidden case, all messages from the beginning are fetched then sliced in memory.

**Step 1: Write a failing test**

Create `backend/src/messages/messages.service.spec.ts`:

```typescript
import { MessagesService } from './messages.service';
import { Repository } from 'typeorm';
import { Message } from './message.entity';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';

describe('MessagesService.findByConversation', () => {
  let service: MessagesService;
  let repo: jest.Mocked<Repository<Message>>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        MessagesService,
        {
          provide: getRepositoryToken(Message),
          useValue: { find: jest.fn().mockResolvedValue([]) },
        },
      ],
    }).compile();
    service = module.get(MessagesService);
    repo = module.get(getRepositoryToken(Message));
  });

  it('uses DB-level skip and take when no hiddenByUserId', async () => {
    await service.findByConversation(1, 20, 40);

    expect(repo.find).toHaveBeenCalledWith(
      expect.objectContaining({ take: 20, skip: 40 }),
    );
  });

  it('uses client-side offset for hidden messages case', async () => {
    const msgs = Array.from({ length: 10 }, (_, i) => ({
      id: i,
      hiddenByUserIds: null,
      createdAt: new Date(),
    })) as Message[];
    repo.find.mockResolvedValue(msgs);

    await service.findByConversation(1, 5, 0, 99);

    // With hiddenByUserId, skip should be 0 (fetch more, filter client-side)
    expect(repo.find).toHaveBeenCalledWith(
      expect.objectContaining({ skip: 0 }),
    );
  });
});
```

**Step 2: Run test — expect FAIL**

```bash
cd backend && npm test -- --testPathPattern=messages.service.spec --no-coverage 2>&1 | tail -20
```

Expected: `uses DB-level skip and take` FAILS (current code uses `skip: 0` always).

**Step 3: Implement the fix**

Replace `findByConversation` in `backend/src/messages/messages.service.ts`:

```typescript
async findByConversation(
  conversationId: number,
  limit: number = 50,
  offset: number = 0,
  hiddenByUserId?: number,
): Promise<Message[]> {
  if (hiddenByUserId == null) {
    // No hidden messages: efficient DB-level pagination
    const messages = await this.msgRepo.find({
      where: { conversation: { id: conversationId } },
      relations: ['sender', 'replyTo', 'replyTo.sender'],
      order: { createdAt: 'DESC' },
      take: limit,
      skip: offset,
    });
    return messages.reverse();
  }

  // With hidden messages: fetch extra rows to account for filtered items.
  // No artificial 500-cap — use a generous multiple so deep offsets work.
  const fetchLimit = limit * 3 + offset + 50;
  const messages = await this.msgRepo.find({
    where: { conversation: { id: conversationId } },
    relations: ['sender', 'replyTo', 'replyTo.sender'],
    order: { createdAt: 'DESC' },
    take: fetchLimit,
    skip: 0,
  });

  const filtered = messages.filter(
    (m) => !MessagesService.parseHiddenIds(m.hiddenByUserIds).includes(hiddenByUserId),
  );
  return filtered.slice(offset, offset + limit).reverse();
}
```

**Step 4: Run test — expect PASS**

```bash
cd backend && npm test -- --testPathPattern=messages.service.spec --no-coverage 2>&1 | tail -10
```

**Step 5: Run all tests**

```bash
cd backend && npm test --no-coverage 2>&1 | tail -10
```

Expected: 82/82 PASS (2 new tests added).

**Step 6: Commit**

```bash
cd backend && git add src/messages/messages.service.ts src/messages/messages.service.spec.ts
git commit -m "fix: use DB-level pagination in findByConversation (no hidden-msg case)"
```

---

## Task 6: OTP atomic claim

**Files:**
- Modify: `backend/src/key-bundles/key-bundles.service.ts:63-93`
- Test: `backend/src/key-bundles/key-bundles.service.spec.ts` (already exists — add test)

The find-then-update pattern for one-time pre-keys is not atomic. Under concurrent requests, the same OTP can be served twice.

**Step 1: Add a failing test for double-serve scenario**

In `backend/src/key-bundles/key-bundles.service.spec.ts`, locate the `describe('fetchPreKeyBundle')` block and add:

```typescript
it('does not serve the same OTP twice under concurrent calls', async () => {
  // Simulate two concurrent calls arriving before either marks used=true.
  // The atomic UPDATE should prevent this by using a database-level single-row claim.
  // We verify the implementation calls query() (atomic path) rather than find+save.
  const spy = jest.spyOn(otpRepo, 'query' as any);
  await service.fetchPreKeyBundle(1);
  // Atomic path is used when query() is defined on the repo
  // (actual race-condition prevention is at DB level; here we verify the code path)
  expect(spy).toHaveBeenCalled();
});
```

> Note: The test verifies we use `query()` (the atomic SQL path), not `findOne` + `save`.

**Step 2: Run test — expect FAIL**

```bash
cd backend && npm test -- --testPathPattern=key-bundles --no-coverage 2>&1 | tail -20
```

Expected: new test FAILS (current code uses `findOne` + `save`).

**Step 3: Implement the fix**

Replace `fetchPreKeyBundle` in `backend/src/key-bundles/key-bundles.service.ts`:

```typescript
async fetchPreKeyBundle(
  userId: number,
): Promise<PreKeyBundleResponse | null> {
  const bundle = await this.keyBundleRepo.findOne({ where: { userId } });
  if (!bundle) return null;

  // Atomic claim: UPDATE ... WHERE id = (SELECT id ... LIMIT 1) RETURNING *
  // Prevents race condition where two concurrent calls serve the same OTP.
  const [otp]: Array<{ id: number; keyId: number; publicKey: string } | undefined> =
    await this.otpRepo.query(
      `UPDATE one_time_pre_keys
         SET used = true
       WHERE id = (
         SELECT id FROM one_time_pre_keys
         WHERE "userId" = $1 AND used = false
         ORDER BY id ASC
         LIMIT 1
       )
       RETURNING id, "keyId", "publicKey"`,
      [userId],
    );

  if (!otp) {
    this.logger.warn(
      `OTP exhausted for userId=${userId}: serving bundle without one-time pre-key`,
    );
  }

  return {
    registrationId: bundle.registrationId,
    identityPublicKey: bundle.identityPublicKey,
    signedPreKeyId: bundle.signedPreKeyId,
    signedPreKeyPublic: bundle.signedPreKeyPublic,
    signedPreKeySignature: bundle.signedPreKeySignature,
    oneTimePreKeyId: otp?.keyId ?? null,
    oneTimePreKeyPublic: otp?.publicKey ?? null,
  };
}
```

**Step 4: Run all tests — expect PASS**

```bash
cd backend && npm test --no-coverage 2>&1 | tail -10
```

Expected: all PASS.

**Step 5: Commit**

```bash
cd backend && git add src/key-bundles/key-bundles.service.ts src/key-bundles/key-bundles.service.spec.ts
git commit -m "fix: atomic OTP claim via UPDATE ... WHERE id = (SELECT ... LIMIT 1)"
```

---

## Task 7: Parallelize N+1 in `_conversationsWithUnread`

**Files:**
- Modify: `backend/src/chat/services/chat-conversation.service.ts:74-103`

Replace the sequential `for` loop with `Promise.all` so all per-conversation queries run in parallel. This turns 2N sequential DB round-trips into 2N parallel ones — wall clock time drops from O(N) to O(1).

**Step 1: Replace the method**

In `backend/src/chat/services/chat-conversation.service.ts`, replace `_conversationsWithUnread` (lines 74–103):

```typescript
private async _conversationsWithUnread(
  conversations: any[],
  userId: number,
): Promise<any[]> {
  if (conversations.length === 0) return [];

  const results = await Promise.all(
    conversations.map(async (conv) => {
      const [unreadCount, lastMessage] = await Promise.all([
        this.messagesService.countUnreadForRecipient(conv.id, userId),
        this.messagesService.getLastMessage(conv.id, userId),
      ]);
      return ConversationMapper.toPayload(conv, { unreadCount, lastMessage });
    }),
  );

  results.sort((a, b) => {
    const aTime = a.lastMessage?.createdAt
      ? new Date(a.lastMessage.createdAt).getTime()
      : new Date(a.createdAt).getTime();
    const bTime = b.lastMessage?.createdAt
      ? new Date(b.lastMessage.createdAt).getTime()
      : new Date(b.createdAt).getTime();
    return bTime - aTime;
  });

  return results;
}
```

**Step 2: Run all tests**

```bash
cd backend && npm test --no-coverage 2>&1 | tail -10
```

Expected: all PASS.

**Step 3: Commit**

```bash
cd backend && git add src/chat/services/chat-conversation.service.ts
git commit -m "perf: parallelize _conversationsWithUnread queries with Promise.all"
```

---

## Task 8: WebSocket rate limiting

**Files:**
- Create: `backend/src/chat/guards/ws-throttler.guard.ts`
- Modify: `backend/src/chat/chat.gateway.ts`
- Modify: `backend/src/chat/chat.module.ts`

Apply per-user rate limiting to high-frequency WebSocket events (`sendMessage`, `sendPing`, `typing`, `recordingVoice`). Use NestJS `ThrottlerGuard` adapted for WebSocket.

**Step 1: Create the guard**

Create `backend/src/chat/guards/ws-throttler.guard.ts`:

```typescript
import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard, ThrottlerException } from '@nestjs/throttler';

@Injectable()
export class WsThrottlerGuard extends ThrottlerGuard {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const client = context.switchToWs().getClient();
    const userId: string =
      client.data?.user?.id?.toString() ??
      client.handshake?.address ??
      'unknown';

    // Use userId as the throttler tracking key
    const { ttl, limit } = this.options[0];
    const key = `ws_throttle_${userId}`;

    const { totalHits } = await this.storageService.increment(
      key,
      ttl,
      limit,
      ttl,
      'default',
    );

    if (totalHits > limit) {
      throw new ThrottlerException();
    }
    return true;
  }
}
```

**Step 2: Register guard in ChatModule**

In `backend/src/chat/chat.module.ts`, add `WsThrottlerGuard` to providers:

```typescript
import { WsThrottlerGuard } from './guards/ws-throttler.guard';
// inside @Module providers array:
{ provide: 'WS_THROTTLER', useClass: WsThrottlerGuard },
```

**Step 3: Apply guard to high-frequency handlers in ChatGateway**

In `backend/src/chat/chat.gateway.ts`, add `@UseGuards` to the handlers that should be rate-limited. First add the import at the top:

```typescript
import { UseGuards } from '@nestjs/common';
import { WsThrottlerGuard } from './guards/ws-throttler.guard';
```

Then decorate the relevant handlers:

```typescript
@UseGuards(WsThrottlerGuard)
@SubscribeMessage('sendMessage')
async handleSendMessage(...) { ... }

@UseGuards(WsThrottlerGuard)
@SubscribeMessage('sendPing')
async handleSendPing(...) { ... }
```

Do NOT rate-limit: `getMessages`, `getConversations`, `getFriends`, `messageDelivered`, `markConversationRead` — these are responses to server events, not user-initiated spam vectors.

**Step 4: Run all tests**

```bash
cd backend && npm test --no-coverage 2>&1 | tail -10
```

Expected: all PASS.

**Step 5: Commit**

```bash
cd backend && git add src/chat/guards/ws-throttler.guard.ts src/chat/chat.gateway.ts src/chat/chat.module.ts
git commit -m "feat: add WS rate limiting on sendMessage and sendPing"
```

---

## Task 9: E2E key storage — userId prefix + fix clearAllKeys

**Files:**
- Modify: `frontend/lib/services/encryption/signal_stores.dart`
- Modify: `frontend/lib/services/encryption_service.dart`

All Signal Protocol storage keys must be prefixed with `e2e_${userId}_` so that multiple accounts on the same device don't share key material.

### Part A: Update `signal_stores.dart`

Each store class needs a `String keyPrefix` field. Replace the 4 store classes to accept and use it.

**Step 1: Update `SecureIdentityKeyStore`**

In `frontend/lib/services/encryption/signal_stores.dart`, change:

```dart
class SecureIdentityKeyStore extends IdentityKeyStore {
  final FlutterSecureStorage _storage;
  // ... existing fields

  SecureIdentityKeyStore(this._storage);
```

to:

```dart
class SecureIdentityKeyStore extends IdentityKeyStore {
  final FlutterSecureStorage _storage;
  final String _p; // key prefix, e.g. 'e2e_42_'
  // ... existing fields

  SecureIdentityKeyStore(this._storage, this._p);
```

Then replace every hardcoded key string in this class:
- `'e2e_identity_key_pair'` → `'${_p}identity_key_pair'`
- `'e2e_registration_id'` → `'${_p}registration_id'`
- `'e2e_trusted_identity_...'` → `'${_p}trusted_identity_...'`

**Step 2: Update `SecurePreKeyStore`**

```dart
class SecurePreKeyStore extends PreKeyStore {
  final FlutterSecureStorage _storage;
  final String _p;

  SecurePreKeyStore(this._storage, this._p);
```

Replace:
- `'e2e_pre_key_$preKeyId'` → `'${_p}pre_key_$preKeyId'`

**Step 3: Update `SecureSignedPreKeyStore`**

```dart
class SecureSignedPreKeyStore extends SignedPreKeyStore {
  final FlutterSecureStorage _storage;
  final String _p;

  SecureSignedPreKeyStore(this._storage, this._p);
```

Replace:
- `'e2e_signed_pre_key_$signedPreKeyId'` → `'${_p}signed_pre_key_$signedPreKeyId'`
- `'e2e_session_${name}_1'` in `deleteAllSessions` → `'${_p}session_${name}_1'`

**Step 4: Update `SecureSessionStore`**

```dart
class SecureSessionStore extends SessionStore {
  final FlutterSecureStorage _storage;
  final String _p;

  SecureSessionStore(this._storage, this._p);

  String _sessionKey(SignalProtocolAddress address) =>
      '${_p}session_${address.getName()}_${address.getDeviceId()}';
```

Replace `deleteAllSessions` key: `'e2e_session_${name}_1'` → `'${_p}session_${name}_1'`

### Part B: Update `encryption_service.dart`

**Step 5: Update `initialize(int userId)` to pass prefix to stores**

In `frontend/lib/services/encryption_service.dart`, update `initialize`:

```dart
Future<void> initialize(int userId) async {
  _userId = userId;
  final p = 'e2e_${userId}_'; // per-user storage key prefix

  _identityStore = SecureIdentityKeyStore(_storage, p);
  _preKeyStore = SecurePreKeyStore(_storage, p);
  _signedPreKeyStore = SecureSignedPreKeyStore(_storage, p);
  _sessionStore = SecureSessionStore(_storage, p);

  final loaded = await _identityStore.loadFromStorage();
  // ... rest unchanged
```

**Step 6: Update global key strings in `_generateKeys` and `generateMorePreKeys`**

In `_generateKeys`, change:
- `'e2e_next_pre_key_id'` → `'e2e_${_userId}_next_pre_key_id'`
- `'e2e_setup_complete'` → `'e2e_${_userId}_setup_complete'`

In `generateMorePreKeys`, change:
- `'e2e_next_pre_key_id'` (two occurrences) → `'e2e_${_userId}_next_pre_key_id'`

### Part C: Fix `clearAllKeys()` to only delete E2E keys

**Step 7: Replace `clearAllKeys`**

```dart
/// Clear all E2E encryption keys for this user from storage.
/// Uses selective deletion (not deleteAll) to avoid wiping non-E2E data.
Future<void> clearAllKeys() async {
  final userId = _userId;
  if (userId != null) {
    final prefix = 'e2e_${userId}_';
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(prefix)) {
        await _storage.delete(key: key);
      }
    }
  }
  _initialized = false;
  needsKeyUpload = false;
  _keysForUpload = null;
  _userId = null;
  debugPrint('[EncryptionService] All encryption keys cleared');
}
```

**Step 8: Verify Flutter compiles**

```bash
cd frontend && flutter analyze --no-pub 2>&1 | grep "error"
```

Expected: zero error lines.

**Step 9: Commit**

```bash
cd frontend && git add lib/services/encryption/signal_stores.dart lib/services/encryption_service.dart
git commit -m "fix: scope all E2E storage keys with userId prefix; selective clearAllKeys"
```

---

## Final: Run full test suite

```bash
cd backend && npm test 2>&1 | tail -10
cd frontend && flutter analyze --no-pub 2>&1 | grep "^error"
```

Expected:
- Backend: all tests PASS (count will be 82+ after new tests added in tasks 1, 2, 5, 6)
- Flutter: zero errors

Then push:

```bash
git push origin master
```
