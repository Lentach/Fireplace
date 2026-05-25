# Contacts Tab Design - Archive → Contacts Refactor

**Date:** 2026-02-14
**Status:** Approved
**Approach:** Full Separation (deleteConversationOnly vs unfriend)

---

## Overview

Replace Archive tab with Contacts tab, implementing separate flows for:
- **Delete conversation** (Conversations tab) - removes chat history only, preserves friendship
- **Unfriend** (Contacts tab) - removes friendship + conversation completely

### User Stories

1. **As a user**, I want to delete chat history with a friend without removing them from my contacts, so I can start fresh while staying connected.
2. **As a user**, I want to remove a friend completely from Contacts tab, deleting all traces of our relationship.
3. **As a user**, I want to re-open a chat with a contact after deleting history, starting with an empty conversation.

---

## Architecture Overview

### Two Independent Flows

```
┌─────────────────────────────────────────────────────────────┐
│  CONVERSATIONS TAB                                          │
│  - Swipe-to-delete → deleteConversationOnly                 │
│  - Deletes: messages + conversation entity                  │
│  - Preserves: friend_request (status: ACCEPTED)             │
│  - Result: Friend visible in Contacts, chat empty           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  CONTACTS TAB (new, replaces Archive)                       │
│  - Long-press → dialog → unfriend                           │
│  - Deletes: friend_request + conversation + messages        │
│  - Result: Total reset, new friend request needed           │
└─────────────────────────────────────────────────────────────┘
```

### Key Changes

**Frontend:**
- New screen: `ContactsScreen` (friends list from `ChatProvider.friends`)
- Modified: `ConversationTile` (swipe-to-delete replaces delete icon)
- Removed: PopupMenu "Unfriend" from `ChatDetailScreen`
- `MainShell`: Index 1 → `ContactsScreen` (replaces `ArchivePlaceholderScreen`)

**Backend:**
- New event: `deleteConversationOnly` (messages + conversation only)
- Existing: `unfriend` unchanged (total delete)
- Modified: `startConversation` (can create new conversation for existing friendship)

**Database:**
- No schema changes - friend_request exists independently of conversation

---

## Frontend Components

### 1. New Screen: ContactsScreen

**Location:** `frontend/lib/screens/contacts_screen.dart`

**Features:**
- Displays `ChatProvider.friends` as list of tiles
- Each tile: `AvatarCircle` + username + email (optional)
- **Long-press gesture:** Shows dialog "Remove friend [username]?"
- On confirm: `chat.unfriend(userId)`
- Empty state: "No contacts yet" + icon
- Tap tile: Open chat with contact (calls `startConversation` if needed)

**Layout:**
- Similar to ConversationsScreen but simpler (no last message, no unread badge)
- Uses `GestureDetector` with `onLongPress` callback

---

### 2. Modified: ConversationTile

**Changes:**
- **Remove:** IconButton delete (lines 128-135 in current code)
- **Add:** Swipe-to-delete gesture using `Dismissible` widget
- **Direction:** `DismissDirection.endToStart` (swipe left-to-right)
- **Background:** Red background with `Icons.delete` icon on right side
- **Confirmation:** `confirmDismiss` → shows AlertDialog "Delete conversation?"
- **Action:** On confirm: calls `onDelete()` callback

**Implementation:**
```dart
Dismissible(
  key: Key('conv-${conv.id}'),
  direction: DismissDirection.endToStart,
  background: Container(
    color: Colors.red,
    alignment: Alignment.centerRight,
    padding: EdgeInsets.only(right: 20),
    child: Icon(Icons.delete, color: Colors.white),
  ),
  confirmDismiss: (direction) async {
    return await showDialog<bool>(...);
  },
  onDismissed: (direction) => onDelete(),
  child: /* existing tile content */
)
```

**Package:** Built-in Flutter `Dismissible` widget (no new dependencies)

---

### 3. Modified: ChatDetailScreen

**Changes:**
- **Remove completely:** PopupMenuButton (lines 406-424)
- **Remove:** `_unfriend()` method (lines 185-212)
- AppBar keeps: back button, title (username), avatar (right side)
- **No** three-dot menu

---

### 4. Modified: MainShell

**Changes:**
```dart
// Import
import 'contacts_screen.dart';

// Line 28
const ContactsScreen(), // replaces ArchivePlaceholderScreen

// Bottom nav item (lines 45-47)
BottomNavigationBarItem(
  icon: Icon(Icons.people_outline),
  activeIcon: Icon(Icons.people),
  label: 'Contacts',
),
```

---

### 5. ChatProvider - New Methods

**Add:**
```dart
void deleteConversationOnly(int conversationId) {
  _socketService.emitDeleteConversationOnly(conversationId);
}
```

**Listener:**
```dart
onConversationDeleted: (data) {
  // Backend emits: { conversationId: number }
  final convId = data['conversationId'] as int;
  _conversations.removeWhere((c) => c.id == convId);
  _messages.removeWhere((m) => m.conversationId == convId);
  _lastMessages.remove(convId);
  _unreadCounts.remove(convId);
  if (_activeConversationId == convId) {
    _activeConversationId = null;
    // If ChatDetailScreen is open, it should close/show empty state
  }
  notifyListeners();
}
```

**Existing unchanged:**
- `unfriend(userId)` - calls `_socketService.emitUnfriend(userId)`
- `onUnfriended` - already handles friend removal

---

### 6. SocketService - New Emit

**Add:**
```dart
void emitDeleteConversationOnly(int conversationId) {
  _socket?.emit('deleteConversationOnly', {
    'conversationId': conversationId,
  });
}
```

**Listener in `_setupListeners()`:**
```dart
_socket!.on('conversationDeleted', onConversationDeleted ?? (data) {});
```

---

## Backend Changes

### 1. New DTO: DeleteConversationOnlyDto

**Location:** `backend/src/chat/dto/delete-conversation-only.dto.ts`

```typescript
import { IsInt } from 'class-validator';

export class DeleteConversationOnlyDto {
  @IsInt()
  conversationId: number;
}
```

---

### 2. New Handler: handleDeleteConversationOnly

**Location:** `backend/src/chat/services/chat-conversation.service.ts`

**Logic:**
```typescript
async handleDeleteConversationOnly(
  client: Socket,
  data: any,
  server: Server,
  onlineUsers: Map<number, string>,
) {
  const userId = client.data.user?.id;
  if (!userId) return;

  // 1. Validate DTO
  let dto: DeleteConversationOnlyDto;
  try {
    dto = validateDto(DeleteConversationOnlyDto, data);
  } catch (error) {
    client.emit('error', { message: error.message });
    return;
  }

  // 2. Find conversation
  const conversation = await this.conversationsService.findById(dto.conversationId);
  if (!conversation) {
    client.emit('error', { message: 'Conversation not found' });
    return;
  }

  // 3. Verify user belongs to conversation
  const userBelongs =
    conversation.userOne.id === userId || conversation.userTwo.id === userId;
  if (!userBelongs) {
    client.emit('error', { message: 'Unauthorized' });
    return;
  }

  // 4. Get other user ID
  const otherUserId =
    conversation.userOne.id === userId
      ? conversation.userTwo.id
      : conversation.userOne.id;

  // 5. Delete messages + conversation (wrap in try-catch)
  try {
    await this.messagesService.deleteAllByConversation(dto.conversationId);
    await this.conversationsService.delete(dto.conversationId);
  } catch (error) {
    this.logger.error('Failed to delete conversation:', error);
    client.emit('error', { message: 'Failed to delete conversation' });
    return;
  }

  // 6. Emit to both users
  const payload = { conversationId: dto.conversationId };
  client.emit('conversationDeleted', payload);

  const otherSocketId = onlineUsers.get(otherUserId);
  if (otherSocketId) {
    server.to(otherSocketId).emit('conversationDeleted', payload);
  }

  // 7. Refresh conversations list for both users
  const userConvs = await this.conversationsService.findByUser(userId);
  const userList = await this._conversationsWithUnread(userConvs, userId);
  client.emit('conversationsList', userList);

  if (otherSocketId) {
    const otherConvs = await this.conversationsService.findByUser(otherUserId);
    const otherList = await this._conversationsWithUnread(otherConvs, otherUserId);
    server.to(otherSocketId).emit('conversationsList', otherList);
  }

  this.logger.debug(
    `Conversation ${dto.conversationId} deleted by user ${userId}. Friend relationship preserved.`
  );

  // NOTE: friend_request is NOT deleted - remains ACCEPTED
}
```

---

### 3. Remove: handleDeleteConversation

**Location:** `backend/src/chat/services/chat-conversation.service.ts` (lines 101-181)

**Action:** Delete this method completely.

**Reason:** Replaced by `handleDeleteConversationOnly` (chat history) + existing `handleUnfriend` (total delete).

---

### 4. Unchanged: handleUnfriend

**Location:** `backend/src/chat/services/chat-friend-request.service.ts` (lines 470-600)

**No changes:**
- Calls `friendsService.unfriend()`
- Deletes conversation
- Emits `unfriended`, `conversationsList`, `friendsList`

**Usage:** Only from Contacts tab (long-press)

---

### 5. Modified: ChatGateway

**Add:**
```typescript
@SubscribeMessage('deleteConversationOnly')
async handleDeleteConversationOnly(
  @ConnectedSocket() client: Socket,
  @MessageBody() data: any,
) {
  await this.chatConversationService.handleDeleteConversationOnly(
    client,
    data,
    this.server,
    this.onlineUsers,
  );
}
```

**Remove:**
```typescript
@SubscribeMessage('deleteConversation') // ← delete this entire handler
```

---

### 6. Verify: startConversation

**Current logic:**
- If friendship exists → find or create conversation

**Expected behavior (no code changes needed):**
- Check if friendship exists (friend_request ACCEPTED)
- Check if conversation exists
- If conversation does NOT exist but friendship does: **create new conversation**
- This already works with `findOrCreate()` method

**Verification needed:** Ensure `findOrCreate` creates new conversation when old one was deleted.

---

## Data Flow

### Flow 1: Delete Conversation (Conversations Tab)

```
User A swipes conversation tile
  ↓
Shows "Delete conversation?" dialog
  ↓
User confirms
  ↓
ConversationTile calls onDelete()
  ↓
ConversationsScreen._deleteConversation(convId)
  ↓
ChatProvider.deleteConversationOnly(convId)
  ↓
SocketService.emitDeleteConversationOnly(convId)
  ↓
Backend: handleDeleteConversationOnly
  ├─ Delete messages (all for conversation)
  ├─ Delete conversation entity
  └─ Keep friend_request (ACCEPTED)
  ↓
Backend emits 'conversationDeleted' to both users
  ↓
ChatProvider.onConversationDeleted
  ├─ Remove from _conversations
  ├─ Remove from _messages
  ├─ Remove from _lastMessages
  └─ notifyListeners()
  ↓
UI updates: conversation disappears from list
  ↓
Friend still visible in Contacts tab
```

### Flow 2: Unfriend (Contacts Tab)

```
User A long-presses contact tile
  ↓
Shows "Remove friend [name]?" dialog
  ↓
User confirms
  ↓
ContactsScreen calls chat.unfriend(userId)
  ↓
ChatProvider.unfriend(userId)
  ↓
SocketService.emitUnfriend(userId)
  ↓
Backend: handleUnfriend
  ├─ Delete friend_request
  ├─ Delete conversation (if exists)
  └─ Delete messages
  ↓
Backend emits to both users:
  ├─ 'unfriended' {userId}
  ├─ 'conversationsList'
  └─ 'friendsList'
  ↓
ChatProvider.onUnfriended
  ├─ Remove from _friends
  ├─ Remove from _conversations
  └─ notifyListeners()
  ↓
UI updates:
  ├─ Contact disappears from Contacts tab
  └─ Conversation disappears from Conversations tab
```

### Flow 3: Re-open Chat After Delete

```
User A previously deleted conversation (history gone)
  ↓
User A taps contact in Contacts tab
  ↓
ContactsScreen checks if conversation exists
  ├─ No conversation found
  └─ Calls startConversation(recipientEmail)
  ↓
Backend: handleStartConversation
  ├─ friendship exists? YES (friend_request ACCEPTED)
  ├─ conversation exists? NO
  └─ Create new conversation (findOrCreate)
  ↓
Backend emits:
  ├─ 'conversationsList' (with new conversation)
  └─ 'openConversation' {conversationId}
  ↓
ChatProvider.consumePendingOpen() returns new conversationId
  ↓
Open ChatDetailScreen with new empty conversation
```

---

## Error Handling

### Backend: deleteConversationOnly

**Error scenarios:**

1. **Conversation not found:**
   - Emit: `error` {message: 'Conversation not found'}
   - Frontend: Ignores (conversation already gone from list)

2. **Unauthorized (user doesn't belong to conversation):**
   - Emit: `error` {message: 'Unauthorized'}
   - Frontend: Show top snackbar "Error: Unauthorized"

3. **Database error during deletion:**
   - Catch error, emit `error` {message: 'Failed to delete conversation'}
   - Frontend: Show top snackbar, conversation stays in list
   - User can retry

**Try-catch blocks:**
- Wrap `messagesService.deleteAllByConversation()` + `conversationsService.delete()`
- On error: log, emit error, return (don't continue)

---

### Frontend: Swipe-to-Delete Failure

**If backend returns error:**
- `onError` listener in SocketService shows top snackbar with `data.message`
- Conversation **does NOT disappear** from list (no `conversationDeleted` event)
- User can retry

**Network disconnect during swipe:**
- `deleteConversationOnly` emit is fire-and-forget
- **No optimistic UI** - wait for `conversationDeleted` from backend
- If timeout: conversation remains in list
- User can retry when connection restored

---

### Edge Case: Other User Offline

**Scenario:**
- User A deletes conversation
- User B is offline

**Behavior:**
- Backend emits `conversationDeleted` to User B, but doesn't arrive (offline)
- **On reconnect:** User B gets fresh `conversationsList` from `getConversations()`
- Conversation disappears from User B's list after reconnect

**Result:** Eventual consistency - acceptable for this use case.

---

## Edge Cases

### 1. User A Deletes Conversation, User B Sends Message Simultaneously

**Scenario:**
- User A: swipe-to-delete conversation
- User B (same time): writes message in this chat

**What happens:**
1. Backend receives `deleteConversationOnly` from User A → deletes conversation
2. Backend receives `sendMessage` from User B with `conversationId` that no longer exists
3. Backend: conversation not found → emit error to User B
4. User B sees error "Conversation not found"

**Solution:**
- User B also gets `conversationDeleted` event (was in conversation)
- On receiving `conversationDeleted`, frontend closes ChatDetailScreen (if open)
- Error "Conversation not found" is valid - conversation was deleted

**Implementation:**
- In `onConversationDeleted`: if `_activeConversationId == deletedConvId`:
  - Close chat screen (Navigator.pop if not embedded)
  - Or show empty state "Conversation was deleted"

---

### 2. User A Deletes Conversation, Then User B Unfriends

**Scenario:**
1. User A: delete conversation (swipe)
2. User B: unfriend from Contacts tab

**What happens:**
1. After step 1: conversation gone, friend_request remains
2. After step 2: friend_request deleted, conversation already doesn't exist (no-op)
3. Backend: `conversationsService.delete(convId)` returns "not found" but wrapped in try-catch (non-critical)

**Result:** Works correctly, User A and B are no longer friends.

---

### 3. Re-opening Chat Before Full Deletion (Race Condition)

**Scenario:**
- User A: delete conversation → emit `deleteConversationOnly`
- User A (immediately): tap contact → emit `startConversation`
- Backend processes in order: first `deleteConversationOnly`, then `startConversation`

**What happens:**
1. `deleteConversationOnly`: deletes conversation
2. `startConversation`: friendship exists, conversation doesn't exist → creates new
3. User A gets `conversationDeleted` (old) + `conversationsList` (with new)

**Result:** Works correctly - new conversation created.

---

## Testing Strategy

### Frontend Tests

**Widget tests:**

1. **ContactsScreen:**
   - Renders friends list from `ChatProvider.friends`
   - Long-press shows dialog
   - Confirm calls `chat.unfriend(userId)`
   - Empty state shows "No contacts yet"

2. **ConversationTile (Dismissible):**
   - Swipe left-to-right shows delete background
   - `confirmDismiss` shows dialog
   - Confirm calls `onDelete()`
   - Cancel doesn't call `onDelete()`

3. **ChatDetailScreen:**
   - No PopupMenu (verify no three-dot menu)
   - No `_unfriend` method

**Integration test:**
- Mock ChatProvider
- Tap contact → verify navigates to ChatDetailScreen
- Swipe conversation → verify shows dialog → confirm → verify `deleteConversationOnly` called

---

### Backend Tests

**Unit tests (service):**

1. **handleDeleteConversationOnly:**
   - Happy path: deletes messages + conversation, emits events
   - Conversation not found → emit error
   - Unauthorized (user doesn't belong) → emit error
   - Other user offline → doesn't crash, emits only to online users

2. **handleUnfriend:**
   - Existing tests remain unchanged

**E2E test (manual or automated):**

1. **Delete conversation flow:**
   - User A swipe-to-delete → conversation disappears for A and B
   - Friends still visible in Contacts tab
   - User A tap contact → opens new empty chat

2. **Unfriend flow:**
   - User A long-press contact → unfriend
   - Contact disappears for A and B
   - Conversation disappears for both
   - User A can't send message (no friend)

3. **Edge case: concurrent delete:**
   - User A delete conversation, User B writes message
   - User B gets error + conversation disappears
   - ChatDetailScreen closes (or shows "Conversation deleted")

---

## Implementation Checklist

### Frontend
- [ ] New file: `contacts_screen.dart` (friends list, long-press unfriend)
- [ ] Modify: `conversation_tile.dart` (Dismissible swipe-to-delete)
- [ ] Modify: `chat_detail_screen.dart` (remove PopupMenu unfriend)
- [ ] Modify: `main_shell.dart` (ContactsScreen instead of Archive)
- [ ] Add to `chat_provider.dart`: `deleteConversationOnly()`, `onConversationDeleted`
- [ ] Add to `socket_service.dart`: `emitDeleteConversationOnly()`, listener

### Backend
- [ ] New file: `delete-conversation-only.dto.ts`
- [ ] Add to `chat-conversation.service.ts`: `handleDeleteConversationOnly()`
- [ ] Remove from `chat-conversation.service.ts`: `handleDeleteConversation()` (old)
- [ ] Add to `chat.gateway.ts`: `@SubscribeMessage('deleteConversationOnly')`
- [ ] Remove from `chat.gateway.ts`: `@SubscribeMessage('deleteConversation')` (old)
- [ ] Verify `startConversation`: creates new conversation for existing friendship
- [ ] Export DTO in `chat.dto.ts` barrel

### Documentation
- [ ] Update `CLAUDE.md` §5 WebSocket Event Map
- [ ] Update `CLAUDE.md` §7 Frontend Mechanisms
- [ ] Update `CLAUDE.md` §8 Backend Mechanisms
- [ ] Update `CLAUDE.md` §9 File Map
- [ ] Add to `CLAUDE.md` §13 Recent Changes

---

## Success Criteria

1. ✅ Archive tab replaced with Contacts tab showing all friends
2. ✅ Swipe-to-delete in Conversations removes chat history only
3. ✅ Long-press unfriend in Contacts removes friend completely
4. ✅ After deleting conversation, user can re-open chat with friend (new empty conversation)
5. ✅ No PopupMenu unfriend in ChatDetailScreen
6. ✅ Both users see consistent state (eventual consistency on offline)
7. ✅ All error cases handled gracefully (no crashes)

---

## Notes

- **No database schema changes** - uses existing friend_request and conversation tables
- **Backward compatible** - old `deleteConversation` event removed, but `unfriend` unchanged
- **Telegram/Signal-like UX** - familiar swipe-to-delete gesture
- **Clean separation** - chat history management vs. friendship management
