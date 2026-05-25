# Important Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all "Important" issues from the code review: security hardening, data integrity, performance, and frontend reliability.

**Architecture:** 12 targeted fixes across 7 files — no schema migrations, no new dependencies. Backend fixes use existing TypeORM patterns; frontend fixes use a cancellation flag and a static counter.

**Tech Stack:** NestJS 11 + TypeORM + Flutter/Dart

---

## Already fixed (skip these)
- 1.3 OG image HTTPS validation ✅
- 1.4 @MaxLength on encryptedContent ✅
- 5.2 OG image URL HTTPS ✅

---

## Task 1: Trivial backend hardening (1.5, 1.6, 5.1)

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts:78-79`
- Modify: `backend/src/messages/messages.controller.ts` (voice endpoint)
- Modify: `backend/src/auth/dto/login.dto.ts:12-13`

### Step 1: Remove WS query-string token fallback in `chat.gateway.ts`

Find lines 77-80:
```typescript
const token =
  (client.handshake.auth?.token as string) ||
  (client.handshake.query.token as string);
```
Replace with:
```typescript
const token = client.handshake.auth?.token as string;
```

### Step 2: Add friendship check to voice upload in `messages.controller.ts`

The voice endpoint (`@Post('voice')`) currently has no `@Body('recipientId')` and no friendship check. Replace the entire `uploadVoiceMessage` method:

```typescript
@Post('voice')
@UseGuards(JwtAuthGuard)
@Throttle({ default: { limit: 10, ttl: 60000 } })
@UseInterceptors(
  FileInterceptor('audio', {
    limits: { fileSize: 10 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
      const allowedMimes = [
        'audio/aac', 'audio/mp4', 'audio/m4a', 'audio/mpeg',
        'audio/webm', 'audio/wav', 'audio/wave', 'audio/x-wav',
      ];
      if (!allowedMimes.includes(file.mimetype)) {
        return cb(new BadRequestException('Invalid audio format'), false);
      }
      cb(null, true);
    },
  }),
)
async uploadVoiceMessage(
  @UploadedFile() file: Express.Multer.File,
  @Body('duration') duration: string,
  @Body('recipientId') recipientId: string,
  @Body('expiresIn') expiresIn?: string,
  @Request() req?,
) {
  const sender = req.user;
  const recipientIdNum = parseInt(recipientId, 10);
  if (!recipientId || isNaN(recipientIdNum)) {
    throw new BadRequestException('recipientId is required');
  }

  const recipient = await this.usersService.findById(recipientIdNum);
  if (!recipient) {
    throw new BadRequestException('Recipient not found');
  }

  const areFriends = await this.friendsService.areFriends(sender.id, recipient.id);
  if (!areFriends) {
    throw new BadRequestException('You can only send voice messages to friends');
  }

  const durationNum = parseInt(duration, 10);
  const expiresInNum = expiresIn ? parseInt(expiresIn, 10) : undefined;

  const result = await this.cloudinaryService.uploadVoiceMessage(
    sender.id,
    file.buffer,
    file.mimetype,
    expiresInNum,
  );

  return {
    mediaUrl: result.secureUrl,
    publicId: result.publicId,
    duration: result.duration || durationNum,
  };
}
```

Note: `usersService` and `friendsService` are already injected. The Flutter client must pass `recipientId` in the voice upload form body — check `api_service.dart` and add it to the `uploadVoiceMessage` call there.

### Step 3: Add `@MaxLength` to password in `login.dto.ts`

```typescript
@IsString()
@MaxLength(200)
password: string;
```

Import `MaxLength` is already imported (line 1 has it). If not present, add to the import.

### Step 4: Build and test

```bash
cd backend && npm run build
npm test
```
Expected: 0 errors, 80/80 tests pass.

### Step 5: Commit

```bash
git add backend/src/chat/chat.gateway.ts \
        backend/src/messages/messages.controller.ts \
        backend/src/auth/dto/login.dto.ts
git commit -m "fix: remove WS query-token fallback, add voice friendship check, LoginDto MaxLength"
```

---

## Task 2: Fix Polish strings → English (2.5)

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart:737-746`

### Step 1: Find and replace all three Polish strings

In `_userFriendlySendError()` (around line 732), the Polish strings are:

Current:
```dart
final who = otherName ?? 'Recipient';
return 'Cannot send: $who does not have encryption keys yet. Ask them to open the app.';
```
(This one may already be English from the previous session fix.)

Find the method body and ensure ALL three return strings are English:

```dart
String _userFriendlySendError(Object e, int recipientId) {
  final s = e.toString();
  if (s.contains('Recipient has no key bundle') || s.contains('no key bundle')) {
    final otherName = _conversations
        .where((c) => conv_helpers.getOtherUserId(c, _currentUserId) == recipientId)
        .map((c) => conv_helpers.getOtherUserUsername(c, _currentUserId))
        .firstOrNull;
    final who = otherName ?? 'Recipient';
    return 'Cannot send: $who does not have encryption keys yet. Ask them to open the app.';
  }
  if (e is TimeoutException || s.contains('timed out') || s.contains('Timeout')) {
    return 'Timed out waiting for recipient keys. Try again.';
  }
  if (!_e2eInitialized) {
    return 'Encryption not ready. Wait a moment and try again.';
  }
  return 'Cannot send encrypted message. Recipient may not have encryption enabled – ask them to open the app.';
}
```

### Step 2: Analyze

```bash
cd frontend && flutter analyze 2>&1 | tail -5
```
Expected: 0 new errors/warnings.

### Step 3: Commit

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "fix: replace Polish error strings with English in chat_provider"
```

---

## Task 3: Membership check + batch READ update (3.2, 3.5)

**Files:**
- Modify: `backend/src/chat/services/chat-message.service.ts` (handleMarkConversationRead, ~line 334)
- Modify: `backend/src/messages/messages.service.ts` (markConversationAsReadFromSender, ~line 188)

### Step 1: Add membership check in `handleMarkConversationRead`

In `chat-message.service.ts`, after fetching the conversation (line ~343), add:

```typescript
const conversation = await this.conversationsService.findById(Number(conversationId));
if (!conversation) return;

// ADDED: verify the caller is a member of this conversation
const readerId = user.id;
if (conversation.userOne.id !== readerId && conversation.userTwo.id !== readerId) {
  this.logger.warn(`handleMarkConversationRead: user ${readerId} is not a member of conv ${conversationId}`);
  return;
}

const otherUserId =
  conversation.userOne.id === readerId
    ? conversation.userTwo.id
    : conversation.userOne.id;
```

### Step 2: Replace N-saves loop with batch UPDATE in `messages.service.ts`

Replace `markConversationAsReadFromSender`:

```typescript
async markConversationAsReadFromSender(
  conversationId: number,
  senderId: number,
): Promise<Message[]> {
  // Batch update — single query instead of N individual saves
  await this.msgRepo
    .createQueryBuilder()
    .update(Message)
    .set({ deliveryStatus: MessageDeliveryStatus.READ })
    .where(
      'conversation_id = :convId AND sender_id = :senderId AND delivery_status != :status',
      {
        convId: conversationId,
        senderId,
        status: MessageDeliveryStatus.READ,
      },
    )
    .execute();

  // Return all sender messages in conversation for event emission
  return this.msgRepo.find({
    where: {
      conversation: { id: conversationId },
      sender: { id: senderId },
    },
    relations: ['sender'],
  });
}
```

Note: This returns all messages (including pre-existing READ ones), which causes `messageDelivered` events for already-READ messages — that's idempotent on the frontend and preferable to N queries.

### Step 3: Build and test

```bash
cd backend && npm run build && npm test
```
Expected: 0 errors, 80/80 pass.

### Step 4: Commit

```bash
git add backend/src/chat/services/chat-message.service.ts \
        backend/src/messages/messages.service.ts
git commit -m "fix: membership check in markConversationRead, batch UPDATE for read status"
```

---

## Task 4: Data integrity — race conditions and transaction (2.3, 3.3, 3.4)

**Files:**
- Modify: `backend/src/key-bundles/key-bundles.service.ts:41-50`
- Modify: `backend/src/conversations/conversations.service.ts:19-31`
- Modify: `backend/src/users/users.service.ts` (deleteAccount, ~line 130)

### Step 1: Atomic upsert in `key-bundles.service.ts`

Replace `upsertKeyBundle`:

```typescript
async upsertKeyBundle(userId: number, data: KeyBundleData): Promise<void> {
  // Atomic upsert — handles concurrent connections from same user (e.g. two tabs)
  await this.keyBundleRepo.upsert(
    { userId, ...data },
    { conflictPaths: ['userId'] },
  );
  this.logger.log(`Key bundle upserted for userId=${userId}`);
}
```

### Step 2: Race-safe `findOrCreate` in `conversations.service.ts`

Replace the method:

```typescript
async findOrCreate(userOne: User, userTwo: User): Promise<Conversation> {
  const existing = await this.convRepo.findOne({
    where: [
      { userOne: { id: userOne.id }, userTwo: { id: userTwo.id } },
      { userOne: { id: userTwo.id }, userTwo: { id: userOne.id } },
    ],
  });
  if (existing) return existing;

  try {
    const conv = this.convRepo.create({ userOne, userTwo });
    return await this.convRepo.save(conv);
  } catch {
    // Race condition: another concurrent request inserted first — return theirs
    const race = await this.convRepo.findOne({
      where: [
        { userOne: { id: userOne.id }, userTwo: { id: userTwo.id } },
        { userOne: { id: userTwo.id }, userTwo: { id: userOne.id } },
      ],
    });
    if (race) return race;
    throw new Error(`Failed to find or create conversation between ${userOne.id} and ${userTwo.id}`);
  }
}
```

### Step 3: Wrap `deleteAccount` in a DB transaction in `users.service.ts`

First, add `DataSource` import and injection:

At the top of the file, ensure import:
```typescript
import { DataSource } from 'typeorm';
```

Add to constructor:
```typescript
constructor(
  @InjectRepository(User)
  private usersRepo: Repository<User>,
  @InjectRepository(Conversation)
  private convRepo: Repository<Conversation>,
  @InjectRepository(Message)
  private messageRepo: Repository<Message>,
  @InjectRepository(FriendRequest)
  private friendRequestRepo: Repository<FriendRequest>,
  private cloudinaryService: CloudinaryService,
  private fcmTokensService: FcmTokensService,
  private keyBundlesService: KeyBundlesService,
  private dataSource: DataSource,   // ADD THIS
) {}
```

Then wrap the DB operations in `deleteAccount` in a transaction. The Cloudinary delete (external I/O) stays outside:

```typescript
async deleteAccount(userId: number, password: string): Promise<void> {
  const user = await this.usersRepo.findOne({ where: { id: userId } });
  if (!user) throw new NotFoundException('User not found');

  const valid = await bcrypt.compare(password, user.password);
  if (!valid) throw new UnauthorizedException('Incorrect password');

  // External I/O before transaction (non-transactional by nature)
  if (user.profilePicturePublicId) {
    await this.cloudinaryService.deleteAvatar(user.profilePicturePublicId);
  }

  // Delete FCM tokens and key bundles (these have their own repos but no cascade)
  await this.fcmTokensService.removeByUserId(userId);
  await this.keyBundlesService.deleteByUserId(userId);

  // All DB operations in a single transaction to prevent partial deletion
  await this.dataSource.transaction(async (manager) => {
    const conversations = await manager.find(Conversation, {
      where: [{ userOne: { id: userId } }, { userTwo: { id: userId } }],
    });

    for (const conv of conversations) {
      await manager.delete(Message, { conversation: { id: conv.id } });
      await manager.delete(Conversation, { id: conv.id });
    }

    await manager.delete(FriendRequest, { sender: { id: userId } });
    await manager.delete(FriendRequest, { receiver: { id: userId } });

    await manager.remove(User, user);
  });

  this.auditLogger.log(`deleteAccount success userId=${userId} username=${user.username}`);
}
```

Note: `FcmTokensService.removeByUserId` and `KeyBundlesService.deleteByUserId` use their own repos outside the transaction. This is acceptable — FCM tokens and key bundles can be orphaned briefly if the transaction fails; they will be cleaned up by the user being absent. The critical DB integrity is messages→conversations→user.

### Step 4: Build and test

```bash
cd backend && npm run build && npm test
```
Expected: 0 errors, 80/80 pass.

### Step 5: Commit

```bash
git add backend/src/key-bundles/key-bundles.service.ts \
        backend/src/conversations/conversations.service.ts \
        backend/src/users/users.service.ts
git commit -m "fix: atomic upsertKeyBundle, race-safe findOrCreate, transactional deleteAccount"
```

---

## Task 5: Frontend reliability (4.2, 4.3, 4.4)

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`

All three fixes are in `chat_provider.dart`. Edit in one pass.

### Fix A: Monotonic optimistic ID counter (4.2)

At the class level (near line 28), add a static counter:

```dart
// Monotonic counter for temporary negative message IDs — prevents collision
// if two messages are sent within the same millisecond.
static int _tempIdSeq = 0;
```

In `sendMessage` (around line 616), replace:
```dart
id: -DateTime.now().millisecondsSinceEpoch, // Temporary negative ID
```
with:
```dart
id: -(++ChatProvider._tempIdSeq), // Monotonic temporary negative ID
```

### Fix B: Retry preserves `replyToMessageId` (4.3)

In `retryFailedMessage` (around line 947), replace:
```dart
if (_activeConversationId == conversationId && content.isNotEmpty) {
  sendMessage(content);
}
```
with:
```dart
if (_activeConversationId == conversationId && content.isNotEmpty) {
  sendMessage(content, replyToMessageId: message.replyToMessageId);
}
```

### Fix C: Cancellation flag for `_decryptMessageHistory` (4.4)

Add a field near `_decryptingHistory`:
```dart
bool _decryptingHistory = false;
bool _decryptHistoryCancelled = false;
```

In `disconnect()`, after `_decryptingHistory = false;` add:
```dart
_decryptHistoryCancelled = true;
```

In `connect()` (near the top of the method body), reset it:
```dart
_decryptHistoryCancelled = false;
```

In `_decryptMessageHistory()`, add a guard check at the start of each iteration:

```dart
for (var i = 0; i < sorted.length; i++) {
  if (_decryptHistoryCancelled) break;  // ADD THIS
  final msg = sorted[i];
  // ... rest unchanged
}
```

And at the start of the method itself, reset the flag:
```dart
Future<void> _decryptMessageHistory() async {
  if (_decryptingHistory) return;
  _decryptingHistory = true;
  _decryptHistoryCancelled = false;  // ADD THIS
  // ... rest unchanged
```

### Step 1: Apply all three fixes above

### Step 2: Analyze

```bash
cd frontend && flutter analyze 2>&1 | tail -5
```
Expected: exit 0, no new issues.

### Step 3: Commit

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "fix: monotonic temp ID, retry preserves replyTo, cancel history decrypt on disconnect"
```

---

## Deferred (too large for this plan)

- **2.1 Signed pre-key rotation** — requires rotation schedule + key-bundle versioning. Track as tech debt.
- **3.6 hiddenByUserIds comma-list** — requires new junction table + DB migration. Track as tech debt.

---

## Verification

After all tasks:

```bash
# Backend
cd backend && npm run build && npm test

# Frontend
cd frontend && flutter analyze
```

Expected: 0 build errors, 80/80 tests pass, 0 new lint issues.

Update `CLAUDE.md` after each task to reflect changes.
