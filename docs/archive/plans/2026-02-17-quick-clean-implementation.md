# Quick Clean Refactoring — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove all confirmed dead code, unused exports, and excessive debug prints from frontend and backend.

**Architecture:** Deletion-only refactoring — no new code, no logic changes. Each task is independent and safe to commit separately.

**Tech Stack:** Flutter/Dart (frontend), NestJS/TypeScript (backend)

---

### Task 1: Delete dead screen files (Frontend)

**Files:**
- Delete: `frontend/lib/screens/archive_placeholder_screen.dart`
- Delete: `frontend/lib/screens/friend_requests_screen.dart`
- Delete: `frontend/lib/screens/new_chat_screen.dart`

**Step 1: Delete the 3 files**

```bash
rm frontend/lib/screens/archive_placeholder_screen.dart
rm frontend/lib/screens/friend_requests_screen.dart
rm frontend/lib/screens/new_chat_screen.dart
```

**Step 2: Verify no broken imports**

Run: `cd frontend && flutter analyze`
Expected: No errors related to these files (they have zero imports across the codebase).

**Step 3: Commit**

```bash
git add -u frontend/lib/screens/
git commit -m "refactor: delete 3 unused screen files (345 lines)"
```

---

### Task 2: Remove unused `clearStatus()` from AuthProvider (Frontend)

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart:99-103`

**Step 1: Remove the method**

Delete lines 99-103 from `auth_provider.dart`:

```dart
  // DELETE THIS BLOCK:
  void clearStatus() {
    _statusMessage = null;
    _isError = false;
    notifyListeners();
  }
```

**Step 2: Verify no callers**

Run: `grep -r "clearStatus" frontend/lib/`
Expected: Zero results.

**Step 3: Commit**

```bash
git add frontend/lib/providers/auth_provider.dart
git commit -m "refactor: remove unused clearStatus() from AuthProvider"
```

---

### Task 3: Remove debug prints from `chat_input_bar.dart` (Frontend)

**Files:**
- Modify: `frontend/lib/widgets/chat_input_bar.dart`

**Step 1: Remove all `print('[VOICE]` lines**

Remove all 26 `print(` calls from this file. These are voice recording debug logs (lines 126, 128, 130, 176, 181, 183, 193, 207, 212, 229, 233, 235, 237, 239, 243, 248, 253, 255, 257, 261, 336, 349).

Keep the error handling logic (try-catch), just remove the `print()` calls inside them. For error catch blocks, keep a single `debugPrint()` for the error itself:
- Line 176: `print('Recording error: $e');` → `debugPrint('Recording error: $e');`
- Line 336: `print('Send voice error: $e');` → `debugPrint('Send voice error: $e');`
- Line 248: `print('[VOICE] ERROR: Exception sending voice message: $e');` → `debugPrint('Send voice error: $e');`

All other `print('[VOICE]` calls (success logs, state logs, flow logs) — delete entirely.

**Step 2: Verify**

Run: `cd frontend && flutter analyze`
Expected: No errors.

**Step 3: Commit**

```bash
git add frontend/lib/widgets/chat_input_bar.dart
git commit -m "refactor: remove 23 debug prints from chat_input_bar"
```

---

### Task 4: Clean debug prints from `chat_provider.dart` (Frontend)

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`

**Step 1: Remove verbose debug logs, keep error logs**

17 debugPrint/print calls. Action per line:

**KEEP (error logs — useful):**
- Line 216: `debugPrint('[ChatProvider] Failed to parse lastMessage...')` — error handler, keep
- Line 527: `print('Voice upload error: $e')` — change to `debugPrint('Voice upload error: $e')`
- Line 606: `debugPrint('[ChatProvider] Image upload failed: $e')` — error handler, keep
- Line 798: `debugPrint('[ChatProvider] Reconnect max attempts reached')` — critical info, keep

**DELETE (flow/state logs — not needed):**
- Line 179: `debugPrint('[ChatProvider] Connecting WebSocket...')`
- Line 232-236: `debugPrint('[ChatProvider] onMessageHistory...')` (2 calls)
- Line 326: `debugPrint('[ChatProvider] Received chatHistoryCleared event')`
- Line 330: `debugPrint('[ChatProvider] Received disappearingTimerUpdated event')`
- Line 339: `debugPrint('[ChatProvider] openConversation...')`
- Line 615: `debugPrint('[ChatProvider] Emitted clearChatHistory...')`
- Line 678: `debugPrint('[ChatProvider] Chat history cleared...')`
- Line 692: `debugPrint('[ChatProvider] Disappearing timer updated...')`
- Line 713: `debugPrint('[ChatProvider] Conversation deleted...')`
- Line 772: `debugPrint('[ChatProvider] Disconnecting WebSocket')`
- Line 809: `debugPrint('[ChatProvider] Scheduling reconnect...')`
- Line 814: `debugPrint('[ChatProvider] Reconnecting WebSocket...')`

**Step 2: Verify**

Run: `cd frontend && flutter analyze`
Expected: No errors.

**Step 3: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "refactor: remove 13 debug prints from chat_provider, keep error logs"
```

---

### Task 5: Clean debug prints from `socket_service.dart` (Frontend)

**Files:**
- Modify: `frontend/lib/services/socket_service.dart`

**Step 1: Remove all 6 debugPrint calls**

All are flow logs (not error handlers):
- Line 75: `debugPrint('[SocketService] Received conversationDeleted: $data')`
- Line 132: `debugPrint('[SocketService] Cannot emit clearChatHistory: socket is null')`
- Line 135: `debugPrint('[SocketService] Emitting clearChatHistory...')`
- Line 143: `debugPrint('[SocketService] Emitted deleteConversationOnly...')`
- Line 148: `debugPrint('[SocketService] Cannot emit setDisappearingTimer: socket is null')`
- Line 151: `debugPrint('[SocketService] Emitting setDisappearingTimer...')`

**Step 2: Verify**

Run: `cd frontend && flutter analyze`
Expected: No errors.

**Step 3: Commit**

```bash
git add frontend/lib/services/socket_service.dart
git commit -m "refactor: remove 6 debug prints from socket_service"
```

---

### Task 6: Remove unused exports from backend

**Files:**
- Modify: `backend/src/chat/dto/chat.dto.ts:65-69` — delete `DeleteConversationDto` class
- Modify: `backend/src/chat/mappers/conversation.mapper.ts:35-37` — delete `toPayloadArray()`
- Modify: `backend/src/chat/mappers/user.mapper.ts:13-15` — delete `toPayloadArray()`
- Modify: `backend/src/chat/mappers/friend-request.mapper.ts:16-18` — delete `toPayloadArray()`
- Modify: `backend/src/chat/services/chat-conversation.service.ts:10,15` — remove unused imports

**Step 1: Delete `DeleteConversationDto` from `chat.dto.ts`**

Remove lines 65-69:
```typescript
// DELETE THIS:
export class DeleteConversationDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;
}
```

**Step 2: Remove unused imports from `chat-conversation.service.ts`**

Change line 8-13 from:
```typescript
import {
  StartConversationDto,
  DeleteConversationDto,
  SetDisappearingTimerDto,
  DeleteConversationOnlyDto,
} from '../dto/chat.dto';
```
To:
```typescript
import {
  StartConversationDto,
  SetDisappearingTimerDto,
  DeleteConversationOnlyDto,
} from '../dto/chat.dto';
```

Remove line 15:
```typescript
import { UserMapper } from '../mappers/user.mapper';
```

**Step 3: Delete `toPayloadArray()` from all 3 mappers**

In `conversation.mapper.ts`, delete lines 35-37:
```typescript
  static toPayloadArray(conversations: Conversation[]) {
    return conversations.map((c) => this.toPayload(c));
  }
```

In `user.mapper.ts`, delete lines 13-15:
```typescript
  static toPayloadArray(users: User[]) {
    return users.map((u) => this.toPayload(u));
  }
```

In `friend-request.mapper.ts`, delete lines 16-18:
```typescript
  static toPayloadArray(requests: FriendRequest[]) {
    return requests.map((r) => this.toPayload(r));
  }
```

**Step 4: Verify**

Run: `cd backend && npm run build`
Expected: Compiles with no errors.

**Step 5: Commit**

```bash
git add backend/src/chat/dto/chat.dto.ts backend/src/chat/mappers/ backend/src/chat/services/chat-conversation.service.ts
git commit -m "refactor: remove unused DTO, mapper methods, and imports from backend"
```

---

### Task 7: Final verification

**Step 1: Run frontend analysis**

```bash
cd frontend && flutter analyze
```
Expected: No errors.

**Step 2: Run backend build**

```bash
cd backend && npm run build
```
Expected: Compiles clean.

**Step 3: Verify git status is clean**

```bash
git status
```
Expected: Only committed changes, no leftover modifications.
