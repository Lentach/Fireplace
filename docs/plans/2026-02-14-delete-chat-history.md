# Delete Chat History Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add long-press action tile that permanently deletes all chat messages for both users with circular progress animation

**Architecture:** WebSocket-based real-time sync. Frontend emits `clearChatHistory` → Backend deletes from DB → Backend emits `chatHistoryCleared` to both users → Frontend clears UI

**Tech Stack:** NestJS (backend), Flutter web (frontend), TypeORM, Socket.IO, CustomPaint for animation

**Design Doc:** `docs/plans/2026-02-14-delete-chat-history-design.md`

---

## Task 1: Backend DTO for clearChatHistory

**Files:**
- Create: `backend/src/chat/dto/clear-chat-history.dto.ts`
- Modify: `backend/src/chat/dto/chat.dto.ts` (export new DTO)

**Step 1: Create DTO file**

Create `backend/src/chat/dto/clear-chat-history.dto.ts`:

```typescript
import { IsNumber } from 'class-validator';

export class ClearChatHistoryDto {
  @IsNumber()
  conversationId: number;
}
```

**Step 2: Export DTO from chat.dto.ts**

Add to `backend/src/chat/dto/chat.dto.ts`:

```typescript
export * from './clear-chat-history.dto';
```

**Step 3: Verify TypeScript compiles**

Run: `cd backend && npm run build`
Expected: Build succeeds, no TypeScript errors

**Step 4: Commit**

```bash
git add backend/src/chat/dto/clear-chat-history.dto.ts backend/src/chat/dto/chat.dto.ts
git commit -m "feat(backend): add ClearChatHistoryDto

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: MessagesService.deleteAllByConversation

**Files:**
- Modify: `backend/src/messages/messages.service.ts`

**Step 1: Add deleteAllByConversation method**

Add to `MessagesService` class (after `markConversationAsReadFromSender` method):

```typescript
  /**
   * Delete all messages in a conversation.
   * Used when clearing chat history.
   */
  async deleteAllByConversation(conversationId: number): Promise<void> {
    await this.msgRepo.delete({ conversation: { id: conversationId } });
  }
```

**Step 2: Verify TypeScript compiles**

Run: `cd backend && npm run build`
Expected: Build succeeds

**Step 3: Verify NestJS starts**

Backend should auto-restart (watch mode). Check Docker logs:
```bash
docker-compose logs backend --tail=20
```
Expected: "Nest application successfully started"

**Step 4: Commit**

```bash
git add backend/src/messages/messages.service.ts
git commit -m "feat(backend): add deleteAllByConversation method

Deletes all messages in a conversation for clearing chat history.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: ChatMessageService.handleClearChatHistory

**Files:**
- Modify: `backend/src/chat/services/chat-message.service.ts`

**Step 1: Import ClearChatHistoryDto**

Add to imports at top of file:

```typescript
import { ClearChatHistoryDto } from '../dto/chat.dto';
```

**Step 2: Add handleClearChatHistory method**

Add to `ChatMessageService` class (after `handleMarkConversationRead`):

```typescript
  async handleClearChatHistory(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(ClearChatHistoryDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    // Verify user belongs to this conversation
    const conversation = await this.conversationsService.findById(
      data.conversationId,
    );
    if (!conversation) {
      client.emit('error', { message: 'Conversation not found' });
      return;
    }

    const userBelongs =
      conversation.userOne.id === userId ||
      conversation.userTwo.id === userId;
    if (!userBelongs) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    // Delete all messages
    await this.messagesService.deleteAllByConversation(data.conversationId);

    // Emit to both users
    const otherUserId =
      conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;

    const payload = { conversationId: data.conversationId };

    // Emit to initiating user
    client.emit('chatHistoryCleared', payload);

    // Emit to other user if online
    const otherUserSocketId = onlineUsers.get(otherUserId);
    if (otherUserSocketId) {
      server.to(otherUserSocketId).emit('chatHistoryCleared', payload);
    }

    this.logger.debug(
      `User ${userId} cleared chat history for conversation ${data.conversationId}`,
    );
  }
```

**Step 3: Verify TypeScript compiles**

Run: `cd backend && npm run build`
Expected: Build succeeds

**Step 4: Check backend restart**

Check Docker logs:
```bash
docker-compose logs backend --tail=20
```
Expected: "Nest application successfully started"

**Step 5: Commit**

```bash
git add backend/src/chat/services/chat-message.service.ts
git commit -m "feat(backend): add handleClearChatHistory WebSocket handler

- Validates DTO and user authorization
- Deletes all messages via MessagesService
- Emits chatHistoryCleared to both users

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Register clearChatHistory WebSocket event

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts`

**Step 1: Add @SubscribeMessage decorator**

Add new handler method to `ChatGateway` class (after `@SubscribeMessage('markConversationRead')`):

```typescript
  @SubscribeMessage('clearChatHistory')
  handleClearChatHistory(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleClearChatHistory(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }
```

**Step 2: Verify TypeScript compiles**

Run: `cd backend && npm run build`
Expected: Build succeeds

**Step 3: Check backend logs for subscription**

Check Docker logs:
```bash
docker-compose logs backend --tail=30
```
Expected: See "ChatGateway subscribed to the \"clearChatHistory\" message"

**Step 4: Commit**

```bash
git add backend/src/chat/chat.gateway.ts
git commit -m "feat(backend): register clearChatHistory WebSocket event

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Frontend SocketService.emitClearChatHistory

**Files:**
- Modify: `frontend/lib/services/socket_service.dart`

**Step 1: Add emitClearChatHistory method**

Add method to `SocketService` class (after `emitMessageDelivered`):

```dart
  void emitClearChatHistory(int conversationId) {
    if (_socket == null) {
      debugPrint('[SocketService] Cannot emit clearChatHistory: socket is null');
      return;
    }
    debugPrint('[SocketService] Emitting clearChatHistory for conversation $conversationId');
    _socket!.emit('clearChatHistory', {'conversationId': conversationId});
  }
```

**Step 2: Verify Flutter compiles**

In Flutter terminal, press `r` for hot reload
Expected: Hot reload succeeds, no compilation errors

**Step 3: Commit**

```bash
git add frontend/lib/services/socket_service.dart
git commit -m "feat(frontend): add emitClearChatHistory to SocketService

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: ChatProvider handlers for chat history clearing

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`

**Step 1: Add clearChatHistory method**

Add public method to `ChatProvider` class (after `sendImageMessage`):

```dart
  void clearChatHistory(int conversationId) {
    _socketService.emitClearChatHistory(conversationId);
    debugPrint('[ChatProvider] Emitted clearChatHistory for conversation $conversationId');
  }
```

**Step 2: Add _handleChatHistoryCleared handler**

Add private method to `ChatProvider` class (after `_handlePingReceived`):

```dart
  void _handleChatHistoryCleared(dynamic data) {
    final m = data as Map<String, dynamic>;
    final conversationId = m['conversationId'] as int;

    debugPrint('[ChatProvider] Chat history cleared for conversation $conversationId');

    // Clear messages from memory
    _messages.remove(conversationId);
    _lastMessages.remove(conversationId);

    notifyListeners();
  }
```

**Step 3: Register event listener in connect method**

Find the `onNewPing` listener registration in `connect` method and add after it:

```dart
      onChatHistoryCleared: (data) {
        debugPrint('[ChatProvider] Received chatHistoryCleared event');
        _handleChatHistoryCleared(data);
      },
```

**Step 4: Add onChatHistoryCleared to SocketService constructor**

Modify `SocketService` constructor call in `connect` to include the new callback:

In `socket_service.dart`, add parameter to constructor:
```dart
  final void Function(dynamic data)? onChatHistoryCleared;
```

And in constructor body, register the listener:
```dart
    if (onChatHistoryCleared != null) {
      _socket!.on('chatHistoryCleared', onChatHistoryCleared);
    }
```

**Step 5: Verify Flutter compiles**

In Flutter terminal, press `r` for hot reload
Expected: Hot reload succeeds

**Step 6: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart frontend/lib/services/socket_service.dart
git commit -m "feat(frontend): add chat history clearing handlers

- ChatProvider.clearChatHistory emits WebSocket event
- _handleChatHistoryCleared clears local messages
- Register chatHistoryCleared listener in SocketService

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: CircularProgressPainter for long-press animation

**Files:**
- Modify: `frontend/lib/widgets/chat_action_tiles.dart`

**Step 1: Add CircularProgressPainter class**

Add at the end of `chat_action_tiles.dart` file (after `_TimerDialog` class):

```dart
class _CircularProgressPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color color;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle (light gray)
    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc (red)
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * 3.14159 * progress; // Full circle = 2π
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2, // Start at top (-90 degrees)
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
```

**Step 2: Verify Flutter compiles**

In Flutter terminal, press `r` for hot reload
Expected: Hot reload succeeds

**Step 3: Commit**

```bash
git add frontend/lib/widgets/chat_action_tiles.dart
git commit -m "feat(frontend): add CircularProgressPainter for long-press

Draws red circular progress ring around tile icon.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: _LongPressActionTile widget with animation

**Files:**
- Modify: `frontend/lib/widgets/chat_action_tiles.dart`

**Step 1: Add _LongPressActionTile StatefulWidget**

Add after `_ActionTile` class (before `_TimerDialog`):

```dart
class _LongPressActionTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onLongPressComplete;

  const _LongPressActionTile({
    required this.icon,
    required this.color,
    required this.onLongPressComplete,
  });

  @override
  State<_LongPressActionTile> createState() => _LongPressActionTileState();
}

class _LongPressActionTileState extends State<_LongPressActionTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(() {
        setState(() {});
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed && _isPressed) {
          // Animation completed while still pressing → trigger action
          widget.onLongPressComplete();
          _reset();
        }
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _isPressed = false;
      _animationController.reset();
    });
  }

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isPressed = true;
    });
    _animationController.forward();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_animationController.status != AnimationStatus.completed) {
      // Released before completion → cancel
      _reset();
    }
  }

  void _onLongPressCancel() {
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      child: Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Progress ring
            if (_isPressed)
              CustomPaint(
                size: const Size(40, 40),
                painter: _CircularProgressPainter(
                  progress: _animationController.value,
                  color: Colors.red,
                ),
              ),
            // Icon
            Icon(widget.icon, size: 24, color: widget.color),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Verify Flutter compiles**

In Flutter terminal, press `r` for hot reload
Expected: Hot reload succeeds

**Step 3: Commit**

```bash
git add frontend/lib/widgets/chat_action_tiles.dart
git commit -m "feat(frontend): add _LongPressActionTile widget

- 1.5s long-press with AnimationController
- Circular progress animation via CustomPaint
- Triggers callback on completion
- Cancels if released early

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Integrate delete tile in ChatActionTiles

**Files:**
- Modify: `frontend/lib/widgets/chat_action_tiles.dart`

**Step 1: Add _handleClearChatHistory method**

Add method to `ChatActionTiles` class (after `_showComingSoon`):

```dart
  void _handleClearChatHistory(BuildContext context) {
    final chat = context.read<ChatProvider>();

    // Guard: Check if conversation is active
    if (chat.activeConversationId == null) {
      showTopSnackBar(context, 'Open a conversation first');
      return;
    }

    final conversationId = chat.activeConversationId!;

    // Clear chat history
    chat.clearChatHistory(conversationId);

    // Show success feedback
    if (context.mounted) {
      showTopSnackBar(context, 'Chat history deleted');
    }

    // Close action panel (navigate back if possible)
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
```

**Step 2: Add delete tile to Row children**

Modify the `Row` children in `build` method - add delete tile FIRST:

```dart
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LongPressActionTile(
            icon: Icons.delete_forever,
            color: iconColor,
            onLongPressComplete: () => _handleClearChatHistory(context),
          ),
          const SizedBox(width: 12),
          _ActionTile(
            icon: Icons.timer_outlined,
            tooltip: 'Timer',
            color: iconColor,
            onTap: () => _showTimerDialog(context),
          ),
          // ... rest of tiles
```

**Step 3: Verify Flutter compiles**

In Flutter terminal, press `r` for hot reload
Expected: Hot reload succeeds, delete tile appears first in action row

**Step 4: Visual test**

1. Open Flutter app in browser
2. Open a chat
3. Click arrow to open action panel
4. Verify delete tile (trash icon) is first position
5. Long-press delete tile → see red circular progress
6. Release before 1.5s → progress cancels
7. Long-press full 1.5s → messages disappear, snackbar shows, panel closes

**Step 5: Commit**

```bash
git add frontend/lib/widgets/chat_action_tiles.dart
git commit -m "feat(frontend): integrate delete tile in ChatActionTiles

- First position before Timer
- Long-press 1.5s triggers clearChatHistory
- Shows success snackbar and closes action panel

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 10: Manual Testing & Documentation

**Step 1: Test happy path (both users online)**

1. Open two browser tabs (User A and User B)
2. Log in as different users
3. Start conversation and send messages
4. User A: Long-press delete tile for 1.5s
5. Verify:
   - [ ] Red circular progress animation completes
   - [ ] Top snackbar "Chat history deleted"
   - [ ] Action panel closes
   - [ ] Messages disappear from User A's chat
   - [ ] Messages disappear from User B's chat (real-time)

**Step 2: Test cancel behavior**

1. User A: Long-press delete tile for 0.5s, then release
2. Verify:
   - [ ] Progress animation stops and resets
   - [ ] Messages remain (not deleted)
   - [ ] No snackbar shown

**Step 3: Test offline user**

1. User A and User B have conversation with messages
2. User B logs out
3. User A: Long-press delete tile for 1.5s
4. Verify User A sees messages deleted
5. User B logs back in
6. Verify:
   - [ ] User B sees empty chat (messages deleted)

**Step 4: Test backend error (silent fallback)**

1. Stop backend: `docker-compose stop backend`
2. User A: Long-press delete tile for 1.5s
3. Verify:
   - [ ] Frontend clears messages locally
   - [ ] Top snackbar shows (optimistic)
4. Restart backend: `docker-compose start backend`
5. Refresh User A's browser
6. Verify:
   - [ ] Messages reappear (weren't actually deleted from DB)

**Step 5: Update CLAUDE.md**

Add to "Recent Changes" section in `CLAUDE.md`:

```markdown
**2026-02-14:**

- **Delete chat history feature (2026-02-14):** Added long-press action tile in ChatActionTiles to permanently delete all messages in a conversation for both users. Frontend: `_LongPressActionTile` widget with 1.5s long-press gesture, circular red progress animation via `CircularProgressPainter`. Backend: New `clearChatHistory` WebSocket event, `MessagesService.deleteAllByConversation()` method. Real-time sync via WebSocket - both users see messages disappear. Silent fallback on errors (local delete only, messages return on refresh). First position in action tiles (before Timer). Files: chat_action_tiles.dart, chat_provider.dart, socket_service.dart, chat-message.service.ts, messages.service.ts, chat.gateway.ts, chat.dto.ts. Design doc: docs/plans/2026-02-14-delete-chat-history-design.md.
```

**Step 6: Commit documentation**

```bash
git add CLAUDE.md
git commit -m "docs: add delete chat history to recent changes

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

**Step 7: Final verification**

Run through all test scenarios one more time:
- [ ] Long-press 1.5s deletes for both users ✅
- [ ] Long-press cancel works ✅
- [ ] Circular progress animation (red ring) ✅
- [ ] Top snackbar appears ✅
- [ ] Action panel closes ✅
- [ ] Real-time sync (second user sees deletion) ✅
- [ ] Offline user sees empty chat after login ✅
- [ ] Backend error → local delete (messages return on refresh) ✅

---

## Success Criteria

✅ Delete tile appears first in action tiles
✅ Long-press 1.5s triggers delete
✅ Circular red progress animation displays
✅ Releasing before 1.5s cancels action
✅ Success snackbar + action panel closes
✅ Messages deleted for both users (global delete)
✅ Real-time sync via WebSocket
✅ Silent fallback on errors (local delete)
✅ Backend deletes from database permanently
✅ CLAUDE.md updated with recent changes

---

## Notes

- Manual testing only (sufficient for MVP scope)
- Silent error handling: failures result in local delete only
- No confirmation dialog (as designed)
- No undo feature (out of scope)
- CircularProgressPainter can be reused for future long-press features
