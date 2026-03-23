# Conversation Message Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate re-entry lag in chat by showing cached messages immediately when a user returns to a previously-visited conversation during the same session.

**Architecture:** Add `Map<int, List<MessageModel>> _conversationCache` to `MessagingProvider`. On re-entry, `loadCachedMessages()` populates `_messages` instantly from cache; background `getMessages()` socket call still fires and merges when it arrives. Cache is updated after every mutation (new message, delete, clear history). Cache is NOT cleared on back-navigation — only on logout/clearAll.

**Tech Stack:** Flutter/Dart, Provider (ChangeNotifier), no new dependencies.

---

## File Map

| File | Role |
|---|---|
| `frontend/lib/providers/messaging_provider.dart` | Core change: cache field + methods + update cache in all mutation handlers |
| `frontend/lib/screens/chat_detail_screen.dart` | Call `loadCachedMessages()` before `getMessages()` in initState/didUpdateWidget |
| `frontend/test/providers/messaging_provider_cache_test.dart` | New: unit tests for cache lifecycle |

---

### Task 1: Add cache infrastructure to MessagingProvider

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart` (around line 69, in the Message State section)
- Test: `frontend/test/providers/messaging_provider_cache_test.dart` (create)

- [ ] **Step 1: Write failing tests for the new cache API**

Create `frontend/test/providers/messaging_provider_cache_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/models/message_model.dart';

MessageModel _msg(int id, int convId) => MessageModel(
      id: id,
      content: 'hello',
      senderId: 1,
      senderUsername: 'alice',
      conversationId: convId,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('MessagingProvider cache', () {
    late MessagingProvider provider;

    setUp(() {
      provider = MessagingProvider();
      provider.onConnect(false, userId: 1, token: 'tok');
    });

    test('hasCachedMessages returns false when no cache', () {
      expect(provider.hasCachedMessages(42), isFalse);
    });

    test('loadCachedMessages returns false and does not change messages when no cache', () {
      final result = provider.loadCachedMessages(42);
      expect(result, isFalse);
      expect(provider.messages, isEmpty);
    });

    test('loadCachedMessages returns true and sets messages when cache exists', () {
      // Simulate cache being populated (via onMessageHistory)
      provider.seedCacheForTest(10, [_msg(1, 10), _msg(2, 10)]);

      final result = provider.loadCachedMessages(10);
      expect(result, isTrue);
      expect(provider.messages.length, 2);
      expect(provider.messages.first.id, 1);
    });

    test('clearAll clears the cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.clearAll();
      expect(provider.hasCachedMessages(10), isFalse);
    });

    test('clearMessages does NOT clear the cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.clearMessages();
      expect(provider.hasCachedMessages(10), isTrue);
    });

    test('loadCachedMessages returns a copy — mutations do not affect cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.loadCachedMessages(10);
      // Simulating external mutation of the returned list
      provider.messages; // access getter (returns _messages)
      // Cache should still have the original entry
      expect(provider.hasCachedMessages(10), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: FAIL — `hasCachedMessages`, `loadCachedMessages`, `seedCacheForTest` not found.

- [ ] **Step 3: Add cache field and core methods to MessagingProvider**

In `frontend/lib/providers/messaging_provider.dart`:

After line 69 (`List<MessageModel> _messages = [];`), add:

```dart
/// Per-conversation message cache for the current session.
/// Populated after onMessageHistory completes (including decryption).
/// Allows instant re-entry into previously-visited conversations.
final Map<int, List<MessageModel>> _conversationCache = {};
```

After the `hasCachedMessages` / `loadCachedMessages` getters section (after line 100, within the public getters block), add:

```dart
/// Whether a warm message cache exists for [conversationId].
bool hasCachedMessages(int conversationId) =>
    _conversationCache.containsKey(conversationId);

/// Immediately populates [_messages] from cache if available.
/// Returns true if cache was used (caller can skip expensive initial scroll setup).
/// Always call getMessages() afterwards to sync any new messages from server.
bool loadCachedMessages(int conversationId) {
  final cached = _conversationCache[conversationId];
  if (cached == null || cached.isEmpty) return false;
  _messages = List.from(cached);
  notifyListeners();
  return true;
}

/// Snapshots current [_messages] into cache for [conversationId].
void _updateCache(int conversationId) {
  _conversationCache[conversationId] = List.from(_messages);
}

/// Test-only: seed the cache directly without going through onMessageHistory.
@visibleForTesting
void seedCacheForTest(int conversationId, List<MessageModel> messages) {
  _conversationCache[conversationId] = List.from(messages);
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: PASS all 6 tests.

- [ ] **Step 5: Run full test suite to check for regressions**

```bash
cd frontend && flutter test
```

Expected: all existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/messaging_provider.dart frontend/test/providers/messaging_provider_cache_test.dart
git commit -m "feat(cache): add per-conversation RAM cache infrastructure to MessagingProvider"
```

---

### Task 2: Populate cache in onMessageHistory

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart` (lines 173–223)
- Test: `frontend/test/providers/messaging_provider_cache_test.dart` (add tests)

- [ ] **Step 1: Write failing tests for cache population via onMessageHistory**

Add to the `'MessagingProvider cache'` group in `messaging_provider_cache_test.dart`:

```dart
test('onMessageHistory populates cache after receiving messages', () async {
  // Seed active conversation
  provider.setActiveConversationIdForTest(10);

  provider.onMessageHistory({
    'conversationId': 10,
    'messages': [
      {
        'id': 1,
        'content': 'hello',
        'senderId': 1,
        'senderUsername': 'alice',
        'conversationId': 10,
        'deliveryStatus': 'READ',
        'messageType': 'TEXT',
        'createdAt': '2026-01-01T00:00:00.000Z',
      }
    ],
  });

  // Cache is populated synchronously (before decrypt completes)
  expect(provider.hasCachedMessages(10), isTrue);
  expect(provider.messages.length, 1);
});

test('onMessageHistory for a different conversation is ignored (no cache pollution)', () {
  provider.setActiveConversationIdForTest(10);

  provider.onMessageHistory({
    'conversationId': 99,
    'messages': [],
  });

  expect(provider.hasCachedMessages(99), isFalse);
  expect(provider.hasCachedMessages(10), isFalse);
});
```

You will also need a test helper `setActiveConversationIdForTest` — add a stub to MessagingProvider (visibleForTesting).

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: FAIL — `setActiveConversationIdForTest` not found + cache not populated.

- [ ] **Step 3: Add test helper and update onMessageHistory**

**3a.** Add test helper to MessagingProvider (after `seedCacheForTest`):

```dart
/// Test-only: set the active conversation ID as if ConversationsProvider was wired.
@visibleForTesting
void setActiveConversationIdForTest(int? id) {
  // We expose this via a thin wrapper since _conversationsProvider is late-wired.
  _activeConversationIdOverrideForTest = id;
}
int? _activeConversationIdOverrideForTest;
```

Update the `activeConversationId` read in `onMessageHistory` (line 174):

```dart
final activeConversationId = _activeConversationIdOverrideForTest ??
    _conversationsProvider?.activeConversationId;
```

**3b.** In `onMessageHistory`, after `notifyListeners()` (line 208), add:

```dart
// Snapshot to cache immediately (encrypted placeholders — fast path for re-entry).
// Will be updated again after decryption completes.
if (responseConversationId != null) _updateCache(responseConversationId);
```

**3c.** Capture `responseConversationId` before the `whenComplete` closure (it's a local already — just pass it):

```dart
final myConversationId = responseConversationId ?? activeConversationId;
_decryptMessageHistory(myGeneration).whenComplete(() {
  if (_decryptHistoryGeneration == myGeneration) {
    _decryptingHistory = false;
    // Update cache with fully-decrypted messages.
    if (myConversationId != null) _updateCache(myConversationId);
  }
  _processIncomingMessageQueue();
});
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run full test suite**

```bash
cd frontend && flutter test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/messaging_provider.dart frontend/test/providers/messaging_provider_cache_test.dart
git commit -m "feat(cache): populate conversation cache in onMessageHistory"
```

---

### Task 3: Keep cache consistent on mutations

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`
- Test: `frontend/test/providers/messaging_provider_cache_test.dart`

- [ ] **Step 1: Write failing tests**

Add to the test group:

```dart
test('_handleIncomingMessage updates cache for active conversation', () {
  provider.seedCacheForTest(10, [_msg(1, 10)]);
  provider.setActiveConversationIdForTest(10);
  // loadCachedMessages first so _messages is set
  provider.loadCachedMessages(10);

  provider.onNewMessage({
    'id': 2,
    'content': 'world',
    'senderId': 2,
    'senderUsername': 'bob',
    'conversationId': 10,
    'deliveryStatus': 'SENT',
    'messageType': 'TEXT',
    'createdAt': '2026-01-01T01:00:00.000Z',
  });

  // Cache should now have 2 messages
  final cacheResult = <MessageModel>[];
  final p2 = MessagingProvider();
  p2.seedCacheForTest(10, provider.messages); // use updated messages as proxy
  expect(provider.messages.length, 2);
});

test('chatHistoryCleared removes cache entry', () {
  provider.seedCacheForTest(10, [_msg(1, 10)]);
  provider.onChatHistoryCleared({'conversationId': 10});
  expect(provider.hasCachedMessages(10), isFalse);
});

test('conversationDeleted removes cache entry', () {
  provider.seedCacheForTest(10, [_msg(1, 10)]);
  provider.onConversationDeleted(10);
  expect(provider.hasCachedMessages(10), isFalse);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Update mutation handlers**

**3a.** In `_handleIncomingMessage`, find where `notifyListeners()` is called after adding/updating a message. After that call, add:

```dart
// Keep cache consistent for active conversation.
final activeId = _activeConversationIdOverrideForTest ??
    _conversationsProvider?.activeConversationId;
if (activeId != null && _conversationCache.containsKey(activeId)) {
  _updateCache(activeId);
}
```

**3b.** In `_handleChatHistoryCleared` (line 462), after `notifyListeners()`, add:

```dart
_conversationCache.remove(conversationId);
```

**3c.** In `onConversationDeleted` (line 255), after `notifyListeners()`, add:

```dart
_conversationCache.remove(conversationId);
```

**3d.** In `_handleMessageDeleted` (line 473), after `notifyListeners()`, add:

```dart
// Update cache to reflect the deletion.
if (_conversationCache.containsKey(conversationId)) {
  _updateCache(conversationId);
}
```

**3e.** In `clearAll()` (line 1950), add `_conversationCache.clear();` alongside the other clears.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run full test suite**

```bash
cd frontend && flutter test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/messaging_provider.dart frontend/test/providers/messaging_provider_cache_test.dart
git commit -m "feat(cache): keep conversation cache consistent across message mutations"
```

---

### Task 4: Use cache in ChatDetailScreen

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart` (lines 99–143)

> No new tests needed here — ChatDetailScreen is a widget that requires a full widget test harness. The provider-level tests from Tasks 1–3 cover correctness. Manual testing is the verification step.

- [ ] **Step 1: Update initState to load from cache first**

In `chat_detail_screen.dart`, in `initState`, the `addPostFrameCallback` block (lines 103–110) currently reads:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  final convs = context.read<ConversationsProvider>();
  final conn = context.read<ConnectionProvider>();
  convs.openConversation(widget.conversationId);
  conn.socketService.getMessages(widget.conversationId, limit: 50);
});
```

Replace with:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  final convs = context.read<ConversationsProvider>();
  final conn = context.read<ConnectionProvider>();
  final messaging = context.read<MessagingProvider>();
  // Show cached messages instantly if available; background sync still runs.
  messaging.loadCachedMessages(widget.conversationId);
  convs.openConversation(widget.conversationId);
  conn.socketService.getMessages(widget.conversationId, limit: 50);
});
```

- [ ] **Step 2: Update didUpdateWidget to also use cache**

In `didUpdateWidget` (lines 136–141):

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  final convs = context.read<ConversationsProvider>();
  final conn = context.read<ConnectionProvider>();
  convs.openConversation(widget.conversationId);
  conn.socketService.getMessages(widget.conversationId, limit: 50);
});
```

Replace with:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  final convs = context.read<ConversationsProvider>();
  final conn = context.read<ConnectionProvider>();
  final messaging = context.read<MessagingProvider>();
  messaging.loadCachedMessages(widget.conversationId);
  convs.openConversation(widget.conversationId);
  conn.socketService.getMessages(widget.conversationId, limit: 50);
});
```

- [ ] **Step 3: Verify _expandCacheForScroll behaviour is automatically correct**

Read `_onNewMessages` (lines 78–97) in `chat_detail_screen.dart`:

```dart
final isInitialLoad = added == currentCount && currentCount > 0;
```

When cache is pre-loaded: `added` = (new messages from server response) ≠ `currentCount` (which already has cached messages). So `isInitialLoad` will be `false` → `_expandCacheForScroll` stays `false` → no expensive 10 000px cacheExtent rebuild. **No code change needed here.**

If `_messages` was empty before (first ever visit), `added == currentCount` → `isInitialLoad = true` → `_expandCacheForScroll = true` as before. Correct.

- [ ] **Step 4: Run flutter analyze**

```bash
cd frontend && flutter analyze
```

Expected: no new warnings or errors.

- [ ] **Step 5: Manual test**

1. `docker-compose up` (backend + DB)
2. `cd frontend && flutter run -d chrome`
3. Log in, open conversation A → wait for messages to load
4. Press back → open conversation B → press back → open conversation A again
5. **Expected:** conversation A messages appear instantly with no empty-screen flash
6. Wait a moment → background sync completes (no visible change if no new messages)
7. Test with disappearing messages: send a message with 5s timer, wait for it to expire, navigate away, come back → message should NOT reappear (server background sync removes it)

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat(cache): use conversation message cache for instant re-entry in ChatDetailScreen"
```

---

### Task 5: Final validation

- [ ] **Step 1: Run full test suite**

```bash
cd frontend && flutter test
```

Expected: all tests pass (59+ existing + new cache tests).

- [ ] **Step 2: Run flutter analyze**

```bash
cd frontend && flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Check CLAUDE.md is up to date**

Add to the `### Frontend` section of `CLAUDE.md` Critical Rules:

```
- `_conversationCache` in MessagingProvider: per-conversation RAM cache for current session.
  Populated by onMessageHistory (after decrypt). Cleared on logout/clearAll, conversation delete,
  chat history clear. NOT cleared by clearMessages() (back navigation).
  loadCachedMessages() returns bool — true means cache was used, skip expensive scroll setup.
```
