# Contacts Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Archive tab with Contacts tab, implementing separate delete conversation (chat history only) and unfriend (total delete) flows.

**Architecture:** Full separation approach - new `deleteConversationOnly` WebSocket event for removing chat history while preserving friendship, and reuse existing `unfriend` for complete removal. Frontend uses swipe-to-delete in Conversations tab and long-press in Contacts tab.

**Tech Stack:** NestJS + TypeORM (backend), Flutter + Provider (frontend), Socket.IO (WebSocket), TypeScript validation DTOs

---

## Task 1: Backend - DeleteConversationOnly DTO and Handler

**Goal:** Create new DTO and handler for deleting conversation without unfriending.

**Files:**
- Create: `backend/src/chat/dto/delete-conversation-only.dto.ts`
- Modify: `backend/src/chat/services/chat-conversation.service.ts`
- Modify: `backend/src/chat/dto/chat.dto.ts` (export new DTO)

### Step 1.1: Create DeleteConversationOnlyDto

Create file: `backend/src/chat/dto/delete-conversation-only.dto.ts`

```typescript
import { IsInt } from 'class-validator';

export class DeleteConversationOnlyDto {
  @IsInt()
  conversationId: number;
}
```

### Step 1.2: Export DTO in barrel file

Modify: `backend/src/chat/dto/chat.dto.ts`

Add export:
```typescript
export { DeleteConversationOnlyDto } from './delete-conversation-only.dto';
```

### Step 1.3: Add handleDeleteConversationOnly method

Modify: `backend/src/chat/services/chat-conversation.service.ts`

Add import at top:
```typescript
import {
  StartConversationDto,
  DeleteConversationDto,
  SetDisappearingTimerDto,
  DeleteConversationOnlyDto, // <-- ADD THIS
} from '../dto/chat.dto';
```

Add method after `handleGetConversations`:

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
  const conversation = await this.conversationsService.findById(
    dto.conversationId,
  );
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
    const otherList = await this._conversationsWithUnread(
      otherConvs,
      otherUserId,
    );
    server.to(otherSocketId).emit('conversationsList', otherList);
  }

  this.logger.debug(
    `Conversation ${dto.conversationId} deleted by user ${userId}. Friend relationship preserved.`,
  );

  // NOTE: friend_request is NOT deleted - remains ACCEPTED
}
```

### Step 1.4: Remove old handleDeleteConversation method

Modify: `backend/src/chat/services/chat-conversation.service.ts`

**Find and DELETE** the entire `handleDeleteConversation` method (lines ~101-181).

This method called `unfriend()` which we don't want - it's replaced by our new handler.

### Step 1.5: Commit backend DTO and handler

```bash
git add backend/src/chat/dto/delete-conversation-only.dto.ts backend/src/chat/dto/chat.dto.ts backend/src/chat/services/chat-conversation.service.ts
git commit -m "feat(backend): add deleteConversationOnly handler

- Create DeleteConversationOnlyDto
- Add handleDeleteConversationOnly method
- Delete old handleDeleteConversation (called unfriend)
- Preserves friend_request while deleting messages + conversation"
```

---

## Task 2: Backend - Register WebSocket Event in Gateway

**Goal:** Wire up new handler to WebSocket gateway and remove old event.

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts`

### Step 2.1: Add @SubscribeMessage handler

Modify: `backend/src/chat/chat.gateway.ts`

Find existing `@SubscribeMessage` handlers (around line 50-100), add new one:

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

### Step 2.2: Remove old deleteConversation handler

Modify: `backend/src/chat/chat.gateway.ts`

**Find and DELETE** the entire `@SubscribeMessage('deleteConversation')` handler.

Search for:
```typescript
@SubscribeMessage('deleteConversation')
```

Delete the entire method.

### Step 2.3: Verify backend compiles

Run: `cd backend && npm run build`

Expected: No TypeScript errors. If errors appear, fix them.

### Step 2.4: Commit gateway changes

```bash
git add backend/src/chat/chat.gateway.ts
git commit -m "feat(backend): register deleteConversationOnly WebSocket event

- Add @SubscribeMessage('deleteConversationOnly')
- Remove old 'deleteConversation' handler"
```

---

## Task 3: Frontend - SocketService Methods

**Goal:** Add emit and listener for new deleteConversationOnly event.

**Files:**
- Modify: `frontend/lib/services/socket_service.dart`

### Step 3.1: Add emitDeleteConversationOnly method

Modify: `frontend/lib/services/socket_service.dart`

Find existing `emit` methods (like `emitUnfriend`, `emitClearChatHistory`), add after them:

```dart
void emitDeleteConversationOnly(int conversationId) {
  _socket?.emit('deleteConversationOnly', {
    'conversationId': conversationId,
  });
  debugPrint('[SocketService] Emitted deleteConversationOnly: $conversationId');
}
```

### Step 3.2: Add onConversationDeleted parameter and listener

Modify: `frontend/lib/services/socket_service.dart`

**In constructor parameters**, find the list of `Function(dynamic)?` parameters (around line 20-50), add:

```dart
final Function(dynamic)? onConversationDeleted;
```

**In `_setupListeners()` method**, find where other listeners are registered (like `onUnfriended`, `onMessageDelivered`), add:

```dart
_socket!.on('conversationDeleted', (data) {
  debugPrint('[SocketService] Received conversationDeleted: $data');
  onConversationDeleted?.call(data);
});
```

### Step 3.3: Verify Flutter compiles

Run: `cd frontend && flutter analyze`

Expected: No errors. If errors, fix them.

### Step 3.4: Commit socket service changes

```bash
git add frontend/lib/services/socket_service.dart
git commit -m "feat(frontend): add deleteConversationOnly socket methods

- Add emitDeleteConversationOnly() method
- Add onConversationDeleted listener parameter"
```

---

## Task 4: Frontend - ChatProvider Methods

**Goal:** Add ChatProvider methods for deleting conversation and handling event.

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`

### Step 4.1: Add deleteConversationOnly method

Modify: `frontend/lib/providers/chat_provider.dart`

Find existing public methods (like `unfriend`, `deleteConversation`), **REPLACE** the old `deleteConversation` method with:

```dart
void deleteConversationOnly(int conversationId) {
  _socketService.emitDeleteConversationOnly(conversationId);
}
```

**Note:** This replaces the old method that may have existed. The new one does NOT call unfriend.

### Step 4.2: Add _handleConversationDeleted listener

Modify: `frontend/lib/providers/chat_provider.dart`

Find existing `_handle` methods (like `_handleUnfriended`, `_handleMessageDelivered`), add after them:

```dart
void _handleConversationDeleted(dynamic data) {
  final convId = data['conversationId'] as int;
  debugPrint('[ChatProvider] Conversation deleted: $convId');

  // Remove from conversations list
  _conversations.removeWhere((c) => c.id == convId);

  // Remove all messages for this conversation
  _messages.removeWhere((m) => m.conversationId == convId);

  // Remove from last messages
  _lastMessages.remove(convId);

  // Remove from unread counts
  _unreadCounts.remove(convId);

  // Clear active conversation if it was deleted
  if (_activeConversationId == convId) {
    _activeConversationId = null;
  }

  notifyListeners();
}
```

### Step 4.3: Register listener in connect() method

Modify: `frontend/lib/providers/chat_provider.dart`

Find where `SocketService` is instantiated in `connect()` method (around line 160-200), find the list of callbacks like `onUnfriended: _handleUnfriended`, add:

```dart
onConversationDeleted: _handleConversationDeleted,
```

### Step 4.4: Verify Flutter compiles

Run: `cd frontend && flutter analyze`

Expected: No errors.

### Step 4.5: Commit ChatProvider changes

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "feat(frontend): add conversation deletion handling

- Add deleteConversationOnly() method
- Add _handleConversationDeleted() listener
- Removes conversation from state while preserving friendship"
```

---

## Task 5: Frontend - ConversationTile Swipe-to-Delete

**Goal:** Replace delete icon button with swipe-to-delete gesture.

**Files:**
- Modify: `frontend/lib/widgets/conversation_tile.dart`

### Step 5.1: Remove IconButton delete

Modify: `frontend/lib/widgets/conversation_tile.dart`

**Find and DELETE** the IconButton delete (lines ~128-135):

```dart
IconButton(
  icon: const Icon(Icons.delete_outline, size: 18),
  color: RpgTheme.accentDark,
  onPressed: onDelete,
  padding: EdgeInsets.zero,
  constraints: const BoxConstraints(),
  tooltip: 'Delete conversation',
),
```

Delete this entire widget from the Column (should be after the timestamp Text).

### Step 5.2: Wrap tile content in Dismissible

Modify: `frontend/lib/widgets/conversation_tile.dart`

The current `build` method returns `Material` widget. Wrap the **entire Material widget** with `Dismissible`:

Find:
```dart
@override
Widget build(BuildContext context) {
  // ... variable declarations ...

  return Material(
    // ... rest of Material content
  );
}
```

Replace with:
```dart
@override
Widget build(BuildContext context) {
  // ... variable declarations ...

  return Dismissible(
    key: Key('conv-tile-${displayName}'),
    direction: DismissDirection.endToStart,
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.delete,
        color: Colors.white,
        size: 28,
      ),
    ),
    confirmDismiss: (direction) async {
      return await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final colorScheme = Theme.of(dialogContext).colorScheme;
          final isDark = RpgTheme.isDark(dialogContext);
          final mutedColor =
              isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;
          return AlertDialog(
            backgroundColor: colorScheme.surface,
            title: Text(
              'Delete Conversation?',
              style: RpgTheme.bodyFont(
                fontSize: 16,
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: Text(
              'This will delete all messages in this conversation. You can re-open the chat later from Contacts.',
              style: RpgTheme.bodyFont(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  'Cancel',
                  style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  'Delete',
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    color: RpgTheme.accentDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
    onDismissed: (direction) => onDelete(),
    child: Material(
      // ... existing Material content (keep unchanged)
    ),
  );
}
```

**Note:** Keep all existing Material widget content unchanged, just wrap it.

### Step 5.3: Update ConversationsScreen to call new method

Modify: `frontend/lib/screens/conversations_screen.dart`

Find `_deleteConversation` method (around line 55-106), change the call from:

```dart
context.read<ChatProvider>().deleteConversation(conversationId);
```

to:

```dart
context.read<ChatProvider>().deleteConversationOnly(conversationId);
```

Also update dialog content text to mention that friend remains in contacts:

Change:
```dart
'This will delete all messages. This action cannot be undone.',
```

to:
```dart
'This will delete all messages. Your contact will remain in the Contacts tab.',
```

### Step 5.4: Verify Flutter compiles

Run: `cd frontend && flutter analyze`

Expected: No errors.

### Step 5.5: Commit swipe-to-delete changes

```bash
git add frontend/lib/widgets/conversation_tile.dart frontend/lib/screens/conversations_screen.dart
git commit -m "feat(frontend): replace delete icon with swipe-to-delete

- Remove IconButton delete from ConversationTile
- Wrap tile in Dismissible widget (swipe left-to-right)
- Show confirmation dialog on swipe
- Update ConversationsScreen to call deleteConversationOnly()"
```

---

## Task 6: Frontend - ContactsScreen

**Goal:** Create new Contacts tab screen showing friends list.

**Files:**
- Create: `frontend/lib/screens/contacts_screen.dart`

### Step 6.1: Create ContactsScreen file

Create file: `frontend/lib/screens/contacts_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/avatar_circle.dart';
import 'chat_detail_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  void _openChatWithContact(BuildContext context, int userId, String email) {
    final chat = context.read<ChatProvider>();

    // Check if conversation exists for this user
    final existingConv = chat.conversations.where((conv) {
      final otherUser = chat.getOtherUser(conv);
      return otherUser?.id == userId;
    }).firstOrNull;

    if (existingConv != null) {
      // Conversation exists, open it
      chat.openConversation(existingConv.id);

      final width = MediaQuery.of(context).size.width;
      if (width < AppConstants.layoutBreakpointDesktop) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(conversationId: existingConv.id),
          ),
        );
      }
    } else {
      // No conversation, start new one (backend will create)
      chat.socket.emitStartConversation(email);
      // consumePendingOpen will handle navigation when backend responds
    }
  }

  void _unfriendContact(BuildContext context, int userId, String username) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final isDark = RpgTheme.isDark(dialogContext);
        final mutedColor =
            isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          title: Text(
            'Remove Friend?',
            style: RpgTheme.bodyFont(
              fontSize: 16,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Remove $username from your contacts? This will delete all conversation history.',
            style: RpgTheme.bodyFont(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.read<ChatProvider>().unfriend(userId);
              },
              child: Text(
                'Remove',
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildContactsList(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = RpgTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? RpgTheme.convItemBorderDark
                : RpgTheme.convItemBorderLight,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Text(
            'Contacts',
            style: RpgTheme.pressStart2P(
              fontSize: 12,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsList(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final friends = chat.friends;
    final isDark = RpgTheme.isDark(context);
    final mutedColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    if (friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 48, color: mutedColor),
              const SizedBox(height: 16),
              Text(
                'No contacts yet',
                style: RpgTheme.bodyFont(fontSize: 16, color: mutedColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Add friends to start chatting',
                style: RpgTheme.bodyFont(
                  fontSize: 13,
                  color: isDark
                      ? RpgTheme.timeColorDark
                      : RpgTheme.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final borderColor =
        isDark ? RpgTheme.convItemBorderDark : RpgTheme.convItemBorderLight;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: friends.length,
      separatorBuilder: (_, index) => Divider(
        height: 1,
        color: borderColor,
      ),
      itemBuilder: (context, index) {
        final friend = friends[index];
        return _buildContactTile(context, friend);
      },
    );
  }

  Widget _buildContactTile(BuildContext context, dynamic friend) {
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryColor =
        isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    final username = friend.username ?? friend.email;
    final email = friend.email as String;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _openChatWithContact(context, friend.id, email),
        onLongPress: () => _unfriendContact(context, friend.id, username),
        borderRadius: BorderRadius.circular(8),
        splashColor: RpgTheme.primaryColor(context).withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              AvatarCircle(
                email: email,
                profilePictureUrl: friend.profilePictureUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: RpgTheme.bodyFont(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      style: RpgTheme.bodyFont(
                        fontSize: 13,
                        color: secondaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Step 6.2: Verify Flutter compiles

Run: `cd frontend && flutter analyze`

Expected: No errors.

### Step 6.3: Commit ContactsScreen

```bash
git add frontend/lib/screens/contacts_screen.dart
git commit -m "feat(frontend): create ContactsScreen with friends list

- Display all friends from ChatProvider
- Tap contact to open chat (creates conversation if needed)
- Long-press to unfriend with confirmation dialog
- Empty state for no contacts"
```

---

## Task 7: Frontend - Remove Unfriend from ChatDetailScreen

**Goal:** Remove three-dot menu and unfriend functionality from chat screen.

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

### Step 7.1: Remove _unfriend method

Modify: `frontend/lib/screens/chat_detail_screen.dart`

**Find and DELETE** the entire `_unfriend()` method (lines ~185-212).

### Step 7.2: Remove PopupMenuButton from AppBar

Modify: `frontend/lib/screens/chat_detail_screen.dart`

Find the AppBar `actions` list (around line 395-424), **DELETE** the PopupMenuButton:

```dart
// Menu (three dots)
PopupMenuButton<String>(
  onSelected: (value) {
    if (value == 'unfriend') {
      _unfriend();
    }
  },
  itemBuilder: (context) => [
    PopupMenuItem(
      value: 'unfriend',
      child: Row(
        children: [
          Icon(Icons.person_remove, color: Colors.red),
          const SizedBox(width: 8),
          const Text('Unfriend'),
        ],
      ),
    ),
  ],
),
```

Delete this entire widget from the `actions` list.

**Keep** the avatar (Padding widget with AvatarCircle) in the actions list.

### Step 7.3: Verify Flutter compiles

Run: `cd frontend && flutter analyze`

Expected: No errors.

### Step 7.4: Commit ChatDetailScreen changes

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat(frontend): remove unfriend from ChatDetailScreen

- Delete _unfriend() method
- Remove three-dot PopupMenuButton from AppBar
- Unfriend now only available from Contacts tab"
```

---

## Task 8: Frontend - Replace Archive with Contacts in MainShell

**Goal:** Update main navigation to show Contacts tab instead of Archive.

**Files:**
- Modify: `frontend/lib/screens/main_shell.dart`

### Step 8.1: Import ContactsScreen

Modify: `frontend/lib/screens/main_shell.dart`

Replace:
```dart
import 'archive_placeholder_screen.dart';
```

with:
```dart
import 'contacts_screen.dart';
```

### Step 8.2: Replace ArchivePlaceholderScreen with ContactsScreen

Modify: `frontend/lib/screens/main_shell.dart`

In the `IndexedStack` children (around line 28), replace:

```dart
const ArchivePlaceholderScreen(),
```

with:

```dart
const ContactsScreen(),
```

### Step 8.3: Update bottom navigation item

Modify: `frontend/lib/screens/main_shell.dart`

In the `bottomNavigationBar` items list (around line 45-47), replace:

```dart
const BottomNavigationBarItem(
  icon: Icon(Icons.archive_outlined),
  label: 'Archive',
),
```

with:

```dart
const BottomNavigationBarItem(
  icon: Icon(Icons.people_outline),
  activeIcon: Icon(Icons.people),
  label: 'Contacts',
),
```

### Step 8.4: Verify Flutter compiles

Run: `cd frontend && flutter analyze`

Expected: No errors.

### Step 8.5: Commit MainShell changes

```bash
git add frontend/lib/screens/main_shell.dart
git commit -m "feat(frontend): replace Archive tab with Contacts

- Import ContactsScreen instead of ArchivePlaceholderScreen
- Update bottom nav icon to people_outline
- Change label from Archive to Contacts"
```

---

## Task 9: Manual E2E Testing

**Goal:** Test all flows manually to ensure everything works.

**Prerequisites:** Backend and frontend running (`docker-compose up` + `flutter run -d chrome`)

### Step 9.1: Test Delete Conversation Flow

**Actions:**
1. Login with User A (create if needed)
2. Add User B as friend and send a message
3. In Conversations tab, swipe conversation tile left-to-right
4. Verify red delete background appears
5. Confirm delete in dialog
6. Verify conversation disappears from Conversations tab
7. Switch to Contacts tab → verify User B is still there
8. Tap User B in Contacts → verify opens new empty chat

**Expected:**
- Swipe gesture works smoothly
- Dialog shows correct text (mentions Contacts tab)
- Conversation removed from list
- Friend still in Contacts
- Can re-open chat (new empty conversation)

### Step 9.2: Test Unfriend Flow

**Actions:**
1. In Contacts tab, long-press a contact
2. Verify dialog appears "Remove friend?"
3. Confirm removal
4. Verify contact disappears from Contacts tab
5. Switch to Conversations tab → verify conversation also gone

**Expected:**
- Long-press shows dialog
- Contact removed from list
- Conversation also removed
- Cannot send messages to unfriended user

### Step 9.3: Test ChatDetailScreen (no unfriend button)

**Actions:**
1. Open any conversation
2. Check AppBar

**Expected:**
- No three-dot menu button
- Only back button, title, and avatar visible

### Step 9.4: Test Both Users (Multi-Device)

**Actions:**
1. User A deletes conversation (swipe)
2. Verify User B sees conversation disappear
3. Verify User B still sees User A in Contacts
4. User A unfriends User B from Contacts
5. Verify User B sees User A disappear from Contacts

**Expected:**
- Real-time sync works
- Both users see consistent state

### Step 9.5: Document any issues

If any issues found:
- Note them down
- Fix blocking issues before proceeding
- Create follow-up tasks for non-critical issues

---

## Task 10: Update Documentation

**Goal:** Update CLAUDE.md with new feature details.

**Files:**
- Modify: `CLAUDE.md`

### Step 10.1: Update §5 WebSocket Event Map

Modify: `CLAUDE.md` section 5

**Remove** row for `deleteConversation` event.

**Add** row for `deleteConversationOnly`:

```markdown
| **deleteConversationOnly** | ChatConversationService.handleDeleteConversationOnly | `conversationDeleted` (convId), `conversationsList` | To other user: `conversationDeleted` (convId), `conversationsList` |
```

Add description for payload:
```markdown
- **conversationDeleted:** `{ conversationId: number }`
```

### Step 10.2: Update §7 Frontend Mechanisms

Modify: `CLAUDE.md` section 7.7 (or create new subsection)

Add:

```markdown
### 7.X Delete Conversation vs Unfriend

- **Delete conversation (Conversations tab):** Swipe-to-delete → calls `deleteConversationOnly()` → removes only chat history (messages + conversation entity), preserves friend_request. Friend remains in Contacts tab.
- **Unfriend (Contacts tab):** Long-press → dialog → calls `unfriend(userId)` → removes friend_request + conversation + messages. Total delete, need new friend request to re-connect.
- **Re-opening chat:** After delete conversation, tapping contact in Contacts tab calls `startConversation()` → backend creates new empty conversation (friendship still exists).
```

### Step 10.3: Update §9 File Map

Modify: `CLAUDE.md` section 9

Update table:

| Change | File(s) |
|--------|---------|
| Delete conversation (history only) | chat/services/chat-conversation.service.ts (handleDeleteConversationOnly), chat_provider.dart, socket_service.dart |
| Contacts screen | screens/contacts_screen.dart, main_shell.dart |
| Swipe-to-delete | widgets/conversation_tile.dart (Dismissible) |

### Step 10.4: Update §13 Recent Changes

Modify: `CLAUDE.md` section 13

Add at top:

```markdown
**2026-02-14:**

- **Contacts tab replaces Archive (2026-02-14):** New Contacts tab shows all friends from `ChatProvider.friends`. Long-press contact to unfriend (total delete: friend_request + conversation + messages). Tap contact to open chat (creates new conversation if needed). Frontend: `ContactsScreen`, `MainShell` updated. Design doc: docs/plans/2026-02-14-contacts-tab-design.md.

- **Swipe-to-delete conversations (2026-02-14):** Conversations tab now uses swipe-to-delete gesture (left-to-right) instead of delete icon. Shows confirmation dialog, then calls `deleteConversationOnly` WebSocket event. Removes only chat history (messages + conversation entity), preserves friend_request so friend remains in Contacts. Backend: new `DeleteConversationOnlyDto`, `handleDeleteConversationOnly` method. Frontend: `ConversationTile` wrapped in `Dismissible` widget. Files: chat-conversation.service.ts, conversation_tile.dart, chat_provider.dart, socket_service.dart.

- **Remove unfriend from chat screen (2026-02-14):** Three-dot menu and unfriend option removed from `ChatDetailScreen`. Unfriend now only available from Contacts tab (long-press). Simplifies chat UI, clear separation of concerns. Files: chat_detail_screen.dart.
```

### Step 10.5: Commit documentation

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for Contacts tab feature

- Add deleteConversationOnly to WebSocket Event Map
- Document delete conversation vs unfriend flows
- Update File Map with new components
- Add Recent Changes entries"
```

---

## Task 11: Final Verification and Cleanup

**Goal:** Ensure all changes are committed and feature is complete.

### Step 11.1: Check git status

Run: `git status`

Expected: "working tree clean" (no uncommitted changes)

If uncommitted changes exist, review and commit them.

### Step 11.2: Verify all success criteria

Check design document success criteria:

- [x] Archive tab replaced with Contacts tab showing all friends
- [x] Swipe-to-delete in Conversations removes chat history only
- [x] Long-press unfriend in Contacts removes friend completely
- [x] After deleting conversation, user can re-open chat with friend
- [x] No PopupMenu unfriend in ChatDetailScreen
- [x] Both users see consistent state
- [x] Error cases handled gracefully

### Step 11.3: Run full test suite

**Backend:**
```bash
cd backend
npm run test
```

**Frontend:**
```bash
cd frontend
flutter test
```

Expected: All tests pass. If failures, investigate and fix.

### Step 11.4: Create final summary commit (if needed)

If any final tweaks were made, create a summary commit:

```bash
git add .
git commit -m "feat: Contacts tab complete - replace Archive with friends list

Summary of changes:
- Backend: deleteConversationOnly WebSocket event (preserves friendship)
- Frontend: ContactsScreen with long-press unfriend
- Frontend: Swipe-to-delete in ConversationTile
- Frontend: Remove unfriend from ChatDetailScreen
- Updated CLAUDE.md documentation

Design: docs/plans/2026-02-14-contacts-tab-design.md"
```

### Step 11.5: Push to remote (if applicable)

If working with git remote:

```bash
git log --oneline -10  # Review commits
git push origin master
```

---

## Success Criteria Checklist

- [x] Backend: `deleteConversationOnly` event implemented and registered
- [x] Backend: Old `deleteConversation` handler removed
- [x] Frontend: SocketService has emit + listener for new event
- [x] Frontend: ChatProvider handles conversation deletion
- [x] Frontend: ConversationTile uses swipe-to-delete (Dismissible)
- [x] Frontend: ContactsScreen created with friends list
- [x] Frontend: Long-press in Contacts unfriends
- [x] Frontend: Unfriend removed from ChatDetailScreen
- [x] Frontend: MainShell shows Contacts instead of Archive
- [x] Documentation: CLAUDE.md updated
- [x] Testing: Manual E2E flows verified
- [x] All commits made with clear messages

---

## Notes for Implementation

**Testing Strategy:**
- Manual E2E testing preferred over automated tests (faster for UI features)
- Backend handler already has existing test patterns to follow
- Focus on verifying real-time sync between users

**Common Pitfalls:**
- Forgetting to remove old `deleteConversation` handler (causes conflicts)
- Not wrapping Dismissible confirmDismiss return in async/await
- Forgetting to update `_deleteConversation` call in ConversationsScreen

**Performance:**
- No performance concerns - same DB operations as before
- Swipe gesture is native Flutter (smooth 60fps)

**Rollback Plan:**
- If issues found, revert commits in reverse order
- Backend changes can be reverted independently of frontend
- No database migrations, so rollback is safe
