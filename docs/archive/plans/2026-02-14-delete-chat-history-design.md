# Delete Chat History Feature - Design Document

**Date:** 2026-02-14
**Status:** Approved
**Approach:** WebSocket-based (real-time sync)

---

## Overview

Add a new action tile in ChatActionTiles that allows users to permanently delete entire chat history for both participants through a long-press gesture with visual feedback.

---

## Requirements Summary

- **Trigger:** Long-press (1.5 seconds) on delete tile
- **Scope:** Global delete - removes messages for both users permanently from database
- **Animation:** Circular progress indicator (red) around icon during long-press
- **Cancel:** Releasing before 1.5s cancels the action
- **Success:** Top snackbar + action panel closes
- **Icon:** `Icons.delete_forever` (first position, before Timer tile)
- **Color:** Standard icon color, red progress indicator
- **Error Handling:** Silent fallback - deletes locally if backend fails, messages return on refresh

---

## Architecture

### Event Flow
```
User A long-press (1.5s)
→ Frontend emits: clearChatHistory(conversationId)
→ Backend: MessagesService.deleteAllByConversation(conversationId)
→ Backend emits to BOTH users: chatHistoryCleared(conversationId)
→ Frontend A & B: Clear _messages[conversationId] from ChatProvider
```

### Backend Layer
- New WebSocket event handler in `ChatMessageService.handleClearChatHistory`
- New method `MessagesService.deleteAllByConversation(conversationId)`
  - Uses existing pattern: `this.msgRepo.delete({ conversation: { id } })`
- Emits `chatHistoryCleared` event to both users' sockets

### Frontend Layer
- New `_LongPressActionTile` widget (extends `_ActionTile` with long-press support)
- Circular progress animation during hold
- `ChatProvider._handleChatHistoryCleared` - clears messages and notifies listeners
- `SocketService.emitClearChatHistory` - WebSocket emit wrapper

---

## Components

### Frontend

**1. `_LongPressActionTile` Widget**
```dart
class _LongPressActionTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onLongPressComplete;
}
```
- Uses `GestureDetector` with `onLongPressStart`, `onLongPressEnd`, `onLongPressCancel`
- State: `_isPressed: bool`, `_progress: double` (0.0 → 1.0)
- `AnimationController` (duration: 1500ms)
- Custom painter: `CircularProgressPainter` - draws red ring around icon

**2. ChatProvider Methods**
- `clearChatHistory(conversationId)` - emits WebSocket event
- `_handleChatHistoryCleared(data)` - clears `_messages[conversationId]`, calls `notifyListeners()`

**3. SocketService**
- `emitClearChatHistory(conversationId)` - emits `clearChatHistory` event

### Backend

**1. MessagesService**
```typescript
async deleteAllByConversation(conversationId: number): Promise<void> {
  await this.msgRepo.delete({ conversation: { id: conversationId } });
}
```

**2. ChatMessageService**
```typescript
async handleClearChatHistory(client: Socket, data: any, server: Server, onlineUsers: Map<number, string>)
```
- Validates DTO
- Checks user belongs to conversation
- Calls `MessagesService.deleteAllByConversation`
- Emits `chatHistoryCleared` to both users

**3. DTO**
```typescript
export class ClearChatHistoryDto {
  @IsNumber()
  conversationId: number;
}
```

---

## Data Flow

### Happy Path
1. User A long-press 1.5s → animation completes
2. Frontend A: `socket.emit('clearChatHistory', { conversationId })`
3. Backend: `ChatMessageService.handleClearChatHistory` receives event
4. Backend: Validate DTO, verify user belongs to conversation
5. Backend: `MessagesService.deleteAllByConversation(conversationId)` - deletes from DB
6. Backend: Find socket IDs for both conversation participants (from `onlineUsers` Map)
7. Backend: `server.to(socketIdA).emit('chatHistoryCleared', { conversationId })`
8. Backend: `server.to(socketIdB).emit('chatHistoryCleared', { conversationId })`
9. Frontend A: `_handleChatHistoryCleared` → clears messages, shows top snackbar, closes action panel
10. Frontend B (if online): `_handleChatHistoryCleared` → clears messages silently

### Cancel Path
1. User A long-press 0.5s → releases
2. Frontend: `onLongPressEnd` → `AnimationController.stop()`
3. Frontend: Reset `_progress = 0`, `_isPressed = false`
4. No WebSocket event emitted

### Error Path (Silent Fallback)
1. User A long-press 1.5s → emit `clearChatHistory`
2. Backend: Error (DB down, WebSocket disconnect, etc.)
3. Frontend: No response within timeout (~5s)
4. Frontend: Clears `_messages[conversationId]` locally (optimistic fallback)
5. On next `getMessages` → messages return from backend (not actually deleted)

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| WebSocket disconnect during animation | Animation completes, emit fails silently → local delete only |
| Backend DB error | Backend doesn't emit event → frontend timeout → local delete |
| User doesn't belong to conversation | Backend returns error event → frontend ignores (guard in handler) |
| Conversation doesn't exist | Backend returns error event → frontend ignores |

**Philosophy:** Silent fallback. If backend fails, messages are cleared from UI but remain in database. User sees empty chat until next refresh/reload.

---

## UI/UX Details

**Tile Position:** First position in ChatActionTiles (before Timer)

**Tile Order:**
```
Delete → Timer → Ping → Attachment → Draw → GIF
```

**Visual States:**
- **Idle:** `Icons.delete_forever` in standard icon color (white/accent)
- **Pressing:** Red circular progress indicator grows around icon (0% → 100% over 1.5s)
- **Complete:** Progress reaches 100% → triggers delete action

**No Tooltip:** Consistent with other action tiles (no hover text)

**Success Feedback:**
- Top snackbar: "Chat history deleted"
- Action panel slides closed
- Message list clears instantly

**Notification for Other User:**
- Messages disappear silently (no snackbar or notification)
- WebSocket event triggers automatic UI update

---

## Testing Plan

**Manual Testing (sufficient for current scope):**

- [ ] Long-press 1.5s → deletes messages for both users
- [ ] Long-press 0.5s + release → cancels (no deletion)
- [ ] Circular progress animation displays (red ring around icon)
- [ ] Progress resets if released early
- [ ] Top snackbar appears after successful delete
- [ ] Action panel closes after successful delete
- [ ] Second user sees messages disappear (if online)
- [ ] Offline user sees empty chat after logging in
- [ ] Backend error → local delete only (messages return on refresh)
- [ ] Position: tile appears first in action row

---

## Implementation Notes

**Backend:**
- Follow existing pattern from `conversations.service.ts` line 62-63 (delete messages then conversation)
- Reuse `onlineUsers` Map from ChatGateway to find both users' socket IDs
- Add `@SubscribeMessage('clearChatHistory')` in `chat.gateway.ts`

**Frontend:**
- Create `_LongPressActionTile` as separate widget (can reuse for future features)
- Use `CustomPaint` with `CircularProgressPainter` for progress ring
- Register `chatHistoryCleared` event listener in `SocketService.connect()`
- Add handler in `ChatProvider.onChatHistoryCleared`

**File Modifications:**
- Backend: `messages.service.ts`, `chat-message.service.ts`, `chat.dto.ts`, `chat.gateway.ts`
- Frontend: `chat_action_tiles.dart`, `chat_provider.dart`, `socket_service.dart`

---

## Future Enhancements (Out of Scope)

- Confirmation dialog before delete
- Undo feature (30s window)
- "Delete for me" vs "Delete for everyone" option
- System message placeholder ("Chat history was deleted")
- Notification to other user with timestamp

---

## Approval

**Status:** ✅ Approved by user on 2026-02-14
**Approach:** WebSocket-based (Approach 1)
**Next Step:** Create implementation plan via writing-plans skill
