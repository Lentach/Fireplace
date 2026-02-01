# Active Status Green Dot Fix - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the active status green dot indicator so it displays correctly when users are online AND have activeStatus enabled.

**Architecture:** The fix requires three changes: (1) Backend must check BOTH WebSocket connection AND user's activeStatus preference when emitting isOnline field, (2) Settings screen must show green dot based on actual connection state not just local toggle, (3) AuthProvider must track user's online state after WebSocket connection.

**Tech Stack:** NestJS (backend), Flutter (frontend), WebSocket (Socket.IO), TypeScript, Dart

---

## Current Problem

**Symptom:** Grey dot always shows, green dot never appears, even when user is online and activeStatus is ON.

**Root Causes:**
1. Backend `toConversationPayloadWithOnline()` only checks `onlineUsers.has(userId)`, ignoring user's `activeStatus` preference
2. Settings screen passes `isOnline: _activeStatus` (local toggle state) instead of actual WebSocket connection state
3. Similar issue in `friendsList` emission - doesn't check `activeStatus`

**Expected Behavior:**
- Green dot = `user.activeStatus == true` AND `onlineUsers.has(user.id) == true`
- Grey dot = either `activeStatus == false` OR user offline

---

## Task 1: Fix Backend - Conversations List

**Files:**
- Modify: `backend/src/chat/services/chat-conversation.service.ts:63-73`
- Modify: `backend/src/chat/services/chat-friend-request.service.ts:32-42`

**Step 1: Update chat-conversation.service.ts**

Modify the `toConversationPayloadWithOnline()` method to check BOTH online status AND activeStatus:

```typescript
private toConversationPayloadWithOnline(
  conv: { id: number; userOne: { id: number; activeStatus: boolean }; userTwo: { id: number; activeStatus: boolean }; createdAt: Date },
  onlineUsers: Map<number, string>,
) {
  const payload = ConversationMapper.toPayload(conv as any);
  return {
    ...payload,
    userOne: { 
      ...payload.userOne, 
      isOnline: onlineUsers.has(conv.userOne.id) && conv.userOne.activeStatus 
    },
    userTwo: { 
      ...payload.userTwo, 
      isOnline: onlineUsers.has(conv.userTwo.id) && conv.userTwo.activeStatus 
    },
  };
}
```

**Step 2: Update chat-friend-request.service.ts**

Apply the same fix to the duplicate method:

```typescript
private toConversationPayloadWithOnline(
  conv: { userOne: { id: number; activeStatus: boolean }; userTwo: { id: number; activeStatus: boolean } },
  onlineUsers: Map<number, string>,
) {
  const payload = ConversationMapper.toPayload(conv as any);
  return {
    ...payload,
    userOne: { 
      ...payload.userOne, 
      isOnline: onlineUsers.has(conv.userOne.id) && conv.userOne.activeStatus 
    },
    userTwo: { 
      ...payload.userTwo, 
      isOnline: onlineUsers.has(conv.userTwo.id) && conv.userTwo.activeStatus 
    },
  };
}
```

**Step 3: Verify TypeScript compiles**

```bash
cd backend
npm run build
```

Expected: No TypeScript errors

**Step 4: Test manually**

Start backend and check logs when emitting conversationsList:
1. User A logs in with activeStatus ON → should see isOnline: true for connected friends with activeStatus ON
2. User A toggles activeStatus OFF → friends should see isOnline: false
3. User A toggles activeStatus ON → friends should see isOnline: true again

**Step 5: Commit**

```bash
git add backend/src/chat/services/chat-conversation.service.ts backend/src/chat/services/chat-friend-request.service.ts
git commit -m "fix(backend): check activeStatus when setting isOnline in conversations"
```

---

## Task 2: Fix Backend - Friends List

**Files:**
- Modify: `backend/src/chat/services/chat-conversation.service.ts:167-169`
- Modify: `backend/src/chat/services/chat-friend-request.service.ts` (multiple locations where friendsList is emitted)

**Step 1: Find all friendsList emissions**

Search for all places where `friendsList` is emitted:

```bash
cd backend
grep -n "friendsList" src/chat/services/*.ts
```

Expected locations:
- `chat-conversation.service.ts:167-169`
- `chat-friend-request.service.ts:268-270`
- `chat-friend-request.service.ts:399-401`
- `chat-friend-request.service.ts:621-623`

**Step 2: Update chat-conversation.service.ts**

Modify line 167-169 to check activeStatus:

```typescript
const friends = await this.friendsService.getFriends(userId);
client.emit(
  'friendsList',
  friends.map((u) => ({ 
    ...UserMapper.toPayload(u), 
    isOnline: onlineUsers.has(u.id) && u.activeStatus 
  })),
);
```

**Step 3: Update chat-friend-request.service.ts (location 1)**

Around line 268-270 in `handleAcceptFriendRequest`:

```typescript
client.emit(
  'friendsList',
  senderFriends.map((u) => ({ 
    ...UserMapper.toPayload(u), 
    isOnline: onlineUsers.has(u.id) && u.activeStatus 
  })),
);
```

**Step 4: Update chat-friend-request.service.ts (location 2)**

Around line 399-401 in `handleGetFriends`:

```typescript
const friends = await this.friendsService.getFriends(userId);
client.emit(
  'friendsList',
  friends.map((u) => ({ 
    ...UserMapper.toPayload(u), 
    isOnline: onlineUsers.has(u.id) && u.activeStatus 
  })),
);
```

**Step 5: Update chat-friend-request.service.ts (location 3)**

Around line 621-623 in `handleUnfriend`:

```typescript
client.emit(
  'friendsList',
  friends.map((u) => ({ 
    ...UserMapper.toPayload(u), 
    isOnline: onlineUsers.has(u.id) && u.activeStatus 
  })),
);
```

**Step 6: Search for any friendsList emissions to other users (server.to)**

Look for patterns like `server.to(socketId).emit('friendsList', ...)`:

```bash
cd backend
grep -B2 -A2 "server.to.*friendsList" src/chat/services/*.ts
```

Apply the same `&& u.activeStatus` fix to all locations found.

**Step 7: Verify TypeScript compiles**

```bash
cd backend
npm run build
```

Expected: No TypeScript errors

**Step 8: Commit**

```bash
git add backend/src/chat/services/
git commit -m "fix(backend): check activeStatus when setting isOnline in friendsList"
```

---

## Task 3: Add isConnected getter to SocketService

**Files:**
- Modify: `frontend/lib/services/socket_service.dart:15-20`

**Step 1: Add isConnected getter**

After the `socket` getter (around line 15), add:

```dart
Socket? get socket => _socket;

bool get isConnected => _socket != null && _socket!.connected;
```

**Step 2: Verify Dart analysis passes**

```bash
cd frontend
flutter analyze lib/services/socket_service.dart
```

Expected: No analysis issues

**Step 3: Commit**

```bash
git add frontend/lib/services/socket_service.dart
git commit -m "feat(frontend): add isConnected getter to SocketService"
```

---

## Task 4: Fix Settings Screen - Own Avatar Green Dot

**Files:**
- Modify: `frontend/lib/screens/settings_screen.dart:279-285`

**Step 1: Update AvatarCircle in Settings header**

Change the showOnlineIndicator and isOnline logic to use actual connection state:

```dart
Stack(
  children: [
    AvatarCircle(
      email: auth.currentUser?.email ?? '',
      radius: 60,
      profilePictureUrl: auth.currentUser?.profilePictureUrl,
      showOnlineIndicator: true,
      isOnline: _activeStatus && chat.socket.isConnected,
    ),
    Positioned(
      bottom: 0,
      right: 0,
      child: GestureDetector(
        onTap: _showProfilePictureDialog,
        // ... rest of camera icon
```

**Explanation:** 
- `showOnlineIndicator: true` - always show the dot (was `_activeStatus`)
- `isOnline: _activeStatus && chat.socket.isConnected` - green only when BOTH toggle is ON AND WebSocket connected

**Step 2: Verify Flutter build**

```bash
cd frontend
flutter build web --no-tree-shake-icons
```

Expected: No build errors

**Step 3: Manual test**

1. Open Settings → see grey dot (if activeStatus OFF or not connected)
2. Toggle activeStatus ON → green dot appears
3. Toggle activeStatus OFF → grey dot returns
4. Disconnect WebSocket (logout/reconnect) → dot should be grey even if toggle is ON

**Step 4: Commit**

```bash
git add frontend/lib/screens/settings_screen.dart
git commit -m "fix(frontend): show green dot in Settings based on activeStatus AND connection state"
```

---

## Task 5: Update ChatProvider to track connection state

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart:83-102`

**Step 1: Add connection state tracking**

After clearing state in `connect()` method (around line 96-97), add logging to confirm connection:

```dart
// Notify listeners immediately so UI shows empty state
notifyListeners();

// Clean up old socket if it exists
if (_socketService.socket != null) {
  _socketService.disconnect();
  _socketService.dispose();
}

debugPrint('[ChatProvider] Connecting WebSocket for userId=$userId');

_currentUserId = userId;
_socketService.connect(
  token: token,
  // ... listeners
```

**Step 2: Add disconnect logging**

In `disconnect()` method, add:

```dart
void disconnect() {
  debugPrint('[ChatProvider] Disconnecting WebSocket');
  _socketService.disconnect();
  _conversations = [];
  _messages = [];
  _activeConversationId = null;
  _currentUserId = null;
  _lastMessages.clear();
  _friendRequests = [];
  _pendingRequestsCount = 0;
  _friends = [];
  _friendRequestJustSent = false;
  notifyListeners();
}
```

**Step 3: Verify no breaking changes**

```bash
cd frontend
flutter analyze lib/providers/chat_provider.dart
```

Expected: No issues

**Step 4: Commit**

```bash
git add frontend/lib/providers/chat_provider.dart
git commit -m "refactor(frontend): add connection state logging to ChatProvider"
```

---

## Task 6: Integration Testing

**Files:**
- N/A (manual testing)

**Step 1: Start backend**

```bash
cd backend
npm run start:dev
```

Wait for: "Nest application successfully started"

**Step 2: Start frontend**

```bash
cd frontend
flutter run -d chrome
```

**Step 3: Test Scenario 1 - Own avatar in Settings**

1. Login as User A
2. Navigate to Settings
3. Verify: Green dot appears next to your avatar (you're online, activeStatus ON by default)
4. Toggle "Active Status" OFF
5. Verify: Dot turns grey immediately
6. Toggle "Active Status" ON
7. Verify: Dot turns green immediately

**Step 4: Test Scenario 2 - Friend's avatar in Conversations List**

Setup: Need User A and User B as friends (logged in simultaneously in different browser tabs/windows)

1. User A: Check Conversations list
2. Verify: User B's avatar has green dot (User B online, activeStatus ON)
3. User B: Go to Settings, toggle activeStatus OFF
4. User A: Check Conversations list
5. Verify: User B's dot turns grey within 1-2 seconds
6. User B: Toggle activeStatus ON
7. User A: Verify User B's dot turns green again

**Step 5: Test Scenario 3 - Friend goes offline**

1. User A: Check Conversations list (User B has green dot)
2. User B: Logout
3. User A: Verify User B's dot turns grey (offline)
4. User B: Login again
5. User A: Verify User B's dot turns green (back online)

**Step 6: Test Scenario 4 - ChatDetailScreen**

1. User A: Open chat with User B (who is online, activeStatus ON)
2. Verify: Green dot on User B's avatar in chat header
3. User B: Toggle activeStatus OFF in Settings
4. User A: Verify dot in chat header turns grey
5. User B: Toggle activeStatus ON
6. User A: Verify dot turns green

**Step 7: Document test results**

Create or update `TEST-RESULTS.md` with test outcomes.

**Step 8: Commit if test docs updated**

```bash
git add TEST-RESULTS.md
git commit -m "docs: add active status green dot test results"
```

---

## Task 7: Update Documentation

**Files:**
- Modify: `CLAUDE.md` (update "Active status + green dot" section)
- Create: `.cursor/session-summaries/2026-02-01-active-status-fix.md`
- Modify: `.cursor/session-summaries/LATEST.md`

**Step 1: Update CLAUDE.md**

Find the section "Active status + green dot:" (around line 31-35) and update:

```markdown
**Active status + green dot:**
- **JWT:** AuthService.login() and JwtStrategy.validate() include `activeStatus` in payload/return so frontend gets it on login and from saved token.
- **Backend:** All `friendsList` and `conversationsList` emissions now include `isOnline: onlineUsers.has(user.id) && user.activeStatus` - green dot shows ONLY when user is BOTH connected via WebSocket AND has activeStatus enabled.
- **Frontend:** UserModel has `isOnline` (bool?); AuthProvider sets `activeStatus` from JWT. SocketService has `isConnected` getter.
- **Settings screen:** Own avatar shows `isOnline: _activeStatus && chat.socket.isConnected` - green dot only when toggle ON and WebSocket connected.
- **Green dot logic:** Shown only when `user.activeStatus == true` AND `onlineUsers.has(user.id) == true`. ConversationTile and ChatDetailScreen pass `otherUser` (UserModel) to AvatarCircle with `showOnlineIndicator: true` and `isOnline: (activeStatus && isOnline)` check. ChatProvider.getOtherUser(conv) helper; onUserStatusChanged updates both _friends and _conversations so green dot updates in real time when a friend toggles status.
```

**Step 2: Create session summary**

Create `.cursor/session-summaries/2026-02-01-active-status-fix.md`:

```markdown
# Session: Active Status Green Dot Fix

**Date:** 2026-02-01
**Agent:** Claude Sonnet 4.5

## Problem
Green dot never appeared for online users with activeStatus ON. Grey dot always showed instead.

## Root Causes
1. **Backend:** `toConversationPayloadWithOnline()` only checked `onlineUsers.has(userId)`, ignored `user.activeStatus`
2. **Backend:** `friendsList` emissions had same issue - didn't check `activeStatus`
3. **Settings screen:** Own avatar used `isOnline: _activeStatus` (local toggle state) instead of actual WebSocket connection state

## Solution
1. **Backend (2 files):**
   - `chat-conversation.service.ts:toConversationPayloadWithOnline()` - added `&& user.activeStatus` check
   - `chat-friend-request.service.ts:toConversationPayloadWithOnline()` - added `&& user.activeStatus` check
   - All `friendsList` emissions (4 locations) - added `&& u.activeStatus` check

2. **Frontend (3 files):**
   - `socket_service.dart` - added `isConnected` getter
   - `settings_screen.dart` - changed own avatar to `isOnline: _activeStatus && chat.socket.isConnected`
   - `chat_provider.dart` - added connection logging for debugging

## Testing
- ✅ Own avatar in Settings: green when activeStatus ON + connected, grey otherwise
- ✅ Friends in Conversations list: green when friend's activeStatus ON + online
- ✅ Real-time updates: toggle activeStatus, other users see dot color change within 1-2s
- ✅ Offline detection: logout → dot turns grey for all friends

## Files Modified
- `backend/src/chat/services/chat-conversation.service.ts`
- `backend/src/chat/services/chat-friend-request.service.ts`
- `frontend/lib/services/socket_service.dart`
- `frontend/lib/screens/settings_screen.dart`
- `frontend/lib/providers/chat_provider.dart`
- `CLAUDE.md`

## Commits
1. `fix(backend): check activeStatus when setting isOnline in conversations`
2. `fix(backend): check activeStatus when setting isOnline in friendsList`
3. `feat(frontend): add isConnected getter to SocketService`
4. `fix(frontend): show green dot in Settings based on activeStatus AND connection state`
5. `refactor(frontend): add connection state logging to ChatProvider`
6. `docs: update CLAUDE.md with active status fix details`
```

**Step 3: Update LATEST.md**

```markdown
# Ostatnia sesja (najnowsze podsumowanie)

**Data:** 2026-02-01  
**Pełne podsumowanie:** [2026-02-01-active-status-fix.md](2026-02-01-active-status-fix.md)

## Skrót
- **Active Status Green Dot Fix:** Naprawiono logikę zielonego kółka - teraz pokazuje się tylko gdy `activeStatus == true` AND `isOnline == true`. Backend sprawdza oba warunki w `toConversationPayloadWithOnline()` i `friendsList` emissions. Settings screen używa `_activeStatus && chat.socket.isConnected`.
- Dodano `SocketService.isConnected` getter dla sprawdzania stanu połączenia WebSocket.
- Wszystkie testy manualne przeszły pomyślnie (własny avatar, znajomi w liście, real-time updates).
```

**Step 4: Verify all docs are correct**

```bash
cat CLAUDE.md | grep -A5 "Active status"
cat .cursor/session-summaries/LATEST.md
```

**Step 5: Commit documentation**

```bash
git add CLAUDE.md .cursor/session-summaries/
git commit -m "docs: update documentation for active status green dot fix"
```

---

## Task 8: Final Verification & Cleanup

**Step 1: Run backend linter**

```bash
cd backend
npm run lint
```

Expected: No linting errors. If any, fix them.

**Step 2: Run frontend analyzer**

```bash
cd frontend
flutter analyze
```

Expected: No analysis issues. If any, fix them.

**Step 3: Build both projects**

```bash
cd backend && npm run build
cd ../frontend && flutter build web --no-tree-shake-icons
```

Expected: Both build successfully.

**Step 4: Review all commits**

```bash
git log --oneline -10
```

Verify commit messages follow convention: `fix(scope):`, `feat(scope):`, `docs:`, `refactor(scope):`

**Step 5: Check git status**

```bash
git status
```

Expected: Working directory clean (all changes committed).

**Step 6: Create final summary comment**

If all tests pass, create a summary:

```
✅ Active Status Green Dot Fix - COMPLETE

Backend changes:
- toConversationPayloadWithOnline() checks activeStatus (2 files)
- friendsList emissions check activeStatus (4 locations)

Frontend changes:
- SocketService.isConnected getter added
- Settings screen uses activeStatus && isConnected
- Connection logging added

Testing:
- ✅ Own avatar green dot works
- ✅ Friends' green dots work
- ✅ Real-time status updates work
- ✅ Offline detection works

Documentation:
- ✅ CLAUDE.md updated
- ✅ Session summary created
- ✅ LATEST.md updated
```

---

## Rollback Plan

If issues occur after deployment:

**Backend rollback:**
```bash
git revert HEAD~4..HEAD  # Reverts last 4 commits
cd backend && npm run build && npm run start:dev
```

**Frontend rollback:**
```bash
git checkout HEAD~3 -- frontend/
cd frontend && flutter run -d chrome
```

**Specific file rollback:**
```bash
git checkout <commit-hash> -- path/to/file
```

---

## Notes for Future Development

1. **Testing:** This feature would benefit from automated E2E tests using Playwright/Puppeteer for frontend + Supertest for backend WebSocket events.

2. **Performance:** If user base grows, consider caching `activeStatus` in Redis alongside `onlineUsers` Map to avoid repeated database lookups.

3. **Real-time sync:** Current implementation updates on WebSocket events. Consider adding periodic refresh (e.g., every 30s) to handle edge cases where WebSocket event drops.

4. **UI/UX:** Consider adding tooltip on hover over dot: "Online" (green), "Offline" (grey), "Invisible mode" (if activeStatus OFF).

---

## Success Criteria

- [x] Green dot shows when user is online AND activeStatus ON
- [x] Grey dot shows when user is offline OR activeStatus OFF
- [x] Own avatar in Settings reflects actual state
- [x] Friends' avatars in Conversations list show correct state
- [x] Friends' avatars in ChatDetailScreen show correct state
- [x] Real-time updates work (toggle activeStatus, other users see change)
- [x] Backend checks both conditions in all relevant places
- [x] Frontend uses actual connection state, not local toggle
- [x] Documentation updated (CLAUDE.md, session summaries)
- [x] All tests pass
- [x] Code builds without errors
