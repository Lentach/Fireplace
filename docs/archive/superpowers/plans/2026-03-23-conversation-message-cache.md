# Conversation Message Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate re-entry lag in chat by showing cached messages immediately when a user returns to a previously-visited conversation during the same session.

**Architecture:** Add `Map<int, List<MessageModel>> _conversationCache` to `MessagingProvider`. On re-entry, `loadCachedMessages()` populates `_messages` instantly from cache; background `getMessages()` socket call still fires and merges when it arrives. Cache is updated after every mutation (new message, delete, clear history, delivery status). Cache is NOT cleared on back-navigation or on `onConnect` — only on `clearAll()` (logout).

**Tech Stack:** Flutter/Dart, Provider (ChangeNotifier), no new dependencies.

---

## File Map

| File | Role |
|---|---|
| `frontend/lib/providers/messaging_provider.dart` | Core: cache field + methods + update in all mutation handlers |
| `frontend/lib/screens/chat_detail_screen.dart` | Call `loadCachedMessages()` before `getMessages()` in initState/didUpdateWidget |
| `frontend/test/providers/messaging_provider_cache_test.dart` | New: unit tests for cache lifecycle |

---

### Task 1: Add cache infrastructure to MessagingProvider

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`
- Create: `frontend/test/providers/messaging_provider_cache_test.dart`

- [ ] **Step 1: Write failing tests**

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
      // onConnect signature is: void onConnect(bool isReconnect)
      // userId and token are set separately via dedicated setters.
      provider.onConnect(false);
      provider.setCurrentUserId(1);
      provider.setToken('tok');
    });

    test('hasCachedMessages returns false when no cache', () {
      expect(provider.hasCachedMessages(42), isFalse);
    });

    test('loadCachedMessages returns false when no cache', () {
      final result = provider.loadCachedMessages(42);
      expect(result, isFalse);
      expect(provider.messages, isEmpty);
    });

    test('loadCachedMessages returns true and sets messages when cache exists', () {
      provider.seedCacheForTest(10, [_msg(1, 10), _msg(2, 10)]);

      final result = provider.loadCachedMessages(10);
      expect(result, isTrue);
      expect(provider.messages.length, 2);
      expect(provider.messages.first.id, 1);
    });

    test('loadCachedMessages returns a copy — provider messages are independent of cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.loadCachedMessages(10);
      // Cache must still be intact after loading (List.from copy)
      expect(provider.hasCachedMessages(10), isTrue);
    });

    test('clearAll clears the cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.clearAll();
      expect(provider.hasCachedMessages(10), isFalse);
    });

    test('clearMessages does NOT clear the cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.clearMessages();
      // Cache survives back-navigation (clearMessages is called on back button)
      expect(provider.hasCachedMessages(10), isTrue);
    });

    test('onConnect does NOT clear the cache', () {
      // Cache is session-scoped — a fresh socket connect (same session, same user)
      // must NOT evict cache entries.
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.onConnect(false);
      expect(provider.hasCachedMessages(10), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: compilation error — `hasCachedMessages`, `loadCachedMessages`, `seedCacheForTest` not found.

- [ ] **Step 3: Add cache field and core methods to MessagingProvider**

In `frontend/lib/providers/messaging_provider.dart`:

**3a.** After line 69 (`List<MessageModel> _messages = [];`), add:

```dart
/// Per-conversation message cache for the current session.
/// Populated/updated by onMessageHistory (after decryption) and all mutation handlers.
/// Survives back-navigation (clearMessages) and socket reconnects (onConnect).
/// Cleared only on logout (clearAll).
final Map<int, List<MessageModel>> _conversationCache = {};
```

**3b.** Add a private getter to avoid repeating the override pattern in every handler (add after the `_tokenForReconnect` field, before the E2E section):

```dart
/// Active conversation ID — uses test override if set, otherwise reads from ConversationsProvider.
int? get _effectiveActiveConversationId =>
    _activeConversationIdOverrideForTest ??
    _conversationsProvider?.activeConversationId;

/// Test-only override for activeConversationId.
int? _activeConversationIdOverrideForTest;
```

**3c.** In the public getters section (after line 100), add:

```dart
/// Whether a warm message cache exists for [conversationId].
bool hasCachedMessages(int conversationId) =>
    _conversationCache.containsKey(conversationId);

/// Immediately populates [_messages] from RAM cache if available and calls notifyListeners().
/// Returns true if cache was used — caller can then skip expensive initial scroll setup.
/// Always follow this with getMessages() to sync new messages from server.
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

/// Test-only: set the active conversation ID (replaces ConversationsProvider wiring).
@visibleForTesting
void setActiveConversationIdForTest(int? id) {
  _activeConversationIdOverrideForTest = id;
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: PASS all 7 tests.

- [ ] **Step 5: Run full test suite — check for regressions**

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
- Modify: `frontend/test/providers/messaging_provider_cache_test.dart`

- [ ] **Step 1: Write failing tests**

Add to the `'MessagingProvider cache'` group:

```dart
test('onMessageHistory populates cache for active conversation', () {
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

  // Cache populated synchronously (with encrypted placeholders; decrypted version follows async)
  expect(provider.hasCachedMessages(10), isTrue);
  expect(provider.messages.length, 1);
});

test('onMessageHistory for a different conversation is ignored', () {
  provider.setActiveConversationIdForTest(10);

  provider.onMessageHistory({
    'conversationId': 99,
    'messages': [],
  });

  expect(provider.hasCachedMessages(99), isFalse);
  expect(provider.hasCachedMessages(10), isFalse);
});
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: FAIL — `setActiveConversationIdForTest` not found + cache not populated.

- [ ] **Step 3: Update onMessageHistory to populate cache**

In `onMessageHistory` (line 173), replace every read of `_conversationsProvider?.activeConversationId` with `_effectiveActiveConversationId` (use the new getter from Task 1).

After `notifyListeners()` (line 208), add:

```dart
// Snapshot to cache immediately (may include encrypted placeholders for E2E messages).
// A second snapshot runs after _decryptMessageHistory completes with decrypted content.
if (responseConversationId != null) _updateCache(responseConversationId);
```

Capture the conversationId before the `whenComplete` closure and add a second snapshot after decryption:

```dart
final myConversationId = responseConversationId ?? _effectiveActiveConversationId;
final myGeneration = _decryptHistoryGeneration;
_decryptingHistory = true;
_decryptMessageHistory(myGeneration).whenComplete(() {
  if (_decryptHistoryGeneration == myGeneration) {
    _decryptingHistory = false;
    // Update cache with fully-decrypted content.
    if (myConversationId != null) _updateCache(myConversationId);
  }
  _processIncomingMessageQueue();
});
```

- [ ] **Step 4: Run tests — verify they pass**

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

### Task 3: Keep cache consistent on all mutations

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`
- Modify: `frontend/test/providers/messaging_provider_cache_test.dart`

This task covers five handlers: `_handleIncomingMessage` (both plain and encrypted paths), `_handleMessageDelivered`, `_handleMessageDeleted`, `_handleChatHistoryCleared`, `onConversationDeleted`, and `clearAll`.

- [ ] **Step 1: Write failing tests**

Add to the test group:

```dart
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

test('messageDeleted updates cache and reflects removal', () {
  provider.seedCacheForTest(10, [_msg(1, 10), _msg(2, 10)]);
  provider.setActiveConversationIdForTest(10);
  provider.loadCachedMessages(10);

  provider.onMessageDeleted({
    'messageId': 1,
    'conversationId': 10,
    'forEveryone': true,
  });

  expect(provider.hasCachedMessages(10), isTrue);
  expect(provider.messages.length, 1);
  expect(provider.messages.first.id, 2);
});

test('messageDeleted removes cache entry when list becomes empty', () {
  provider.seedCacheForTest(10, [_msg(1, 10)]);
  provider.setActiveConversationIdForTest(10);
  provider.loadCachedMessages(10);

  provider.onMessageDeleted({
    'messageId': 1,
    'conversationId': 10,
    'forEveryone': true,
  });

  // Empty list → cache entry removed so hasCachedMessages is false
  expect(provider.hasCachedMessages(10), isFalse);
});
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Update _handleIncomingMessage — plain path**

In `_handleIncomingMessage` (line 307), after `_addMessageToState(msg);` (the non-encrypted path), add:

```dart
// Keep cache current for active conversation.
final activeId = _effectiveActiveConversationId;
if (activeId != null && _conversationCache.containsKey(activeId)) {
  _updateCache(activeId);
}
```

- [ ] **Step 4: Update _handleIncomingMessage — encrypted async path**

In `_handleIncomingMessage`, inside the `.then()` callback (after line 302, `notifyListeners();`), add:

```dart
// Update cache with decrypted content (encrypted placeholder was stored on _addMessageToState).
final activeId = _effectiveActiveConversationId;
if (activeId != null && _conversationCache.containsKey(activeId)) {
  _updateCache(activeId);
}
```

- [ ] **Step 5: Update _handleMessageDelivered**

In `_handleMessageDelivered` (line 431), after `notifyListeners()` (line 458), add:

```dart
// Keep delivery status current in cache.
if (conversationId != null && _conversationCache.containsKey(conversationId)) {
  _updateCache(conversationId);
}
```

- [ ] **Step 6: Update _handleMessageDeleted**

In `_handleMessageDeleted` (line 473), after `notifyListeners()` (line 501), add:

```dart
// Reflect deletion in cache; remove entry entirely if the conversation is now empty.
if (_conversationCache.containsKey(conversationId)) {
  final remaining = _messages.where((m) => m.conversationId == conversationId).toList();
  if (remaining.isEmpty) {
    _conversationCache.remove(conversationId);
  } else {
    _updateCache(conversationId);
  }
}
```

- [ ] **Step 7: Update _handleChatHistoryCleared**

In `_handleChatHistoryCleared` (line 462), after `notifyListeners()`, add:

```dart
_conversationCache.remove(conversationId);
```

- [ ] **Step 8: Update onConversationDeleted**

In `onConversationDeleted` (line 255), after `notifyListeners()`, add:

```dart
_conversationCache.remove(conversationId);
```

- [ ] **Step 9: Update clearAll**

In `clearAll()` (line 1950), add alongside the other clears:

```dart
_conversationCache.clear();
```

Note: do NOT add `_conversationCache.clear()` to `onConnect`. The cache is session-scoped — a socket reconnect (same session, same user) must preserve the cache. Only `clearAll()` (logout path) should evict it.

- [ ] **Step 10: Run tests — verify they pass**

```bash
cd frontend && flutter test test/providers/messaging_provider_cache_test.dart
```

Expected: PASS all tests.

- [ ] **Step 11: Run full test suite**

```bash
cd frontend && flutter test
```

Expected: all pass.

- [ ] **Step 12: Commit**

```bash
git add frontend/lib/providers/messaging_provider.dart frontend/test/providers/messaging_provider_cache_test.dart
git commit -m "feat(cache): keep conversation cache consistent across all message mutations"
```

---

### Task 4: Use cache in ChatDetailScreen

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart` (lines 99–143)

- [ ] **Step 1: Update initState**

In `chat_detail_screen.dart`, the `addPostFrameCallback` block in `initState` (lines 103–110):

```dart
// BEFORE:
WidgetsBinding.instance.addPostFrameCallback((_) {
  final convs = context.read<ConversationsProvider>();
  final conn = context.read<ConnectionProvider>();
  convs.openConversation(widget.conversationId);
  conn.socketService.getMessages(widget.conversationId, limit: 50);
});

// AFTER:
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  final convs = context.read<ConversationsProvider>();
  final conn = context.read<ConnectionProvider>();
  final messaging = context.read<MessagingProvider>();
  // Show cached messages instantly if available (eliminates re-entry lag).
  // getMessages() always fires afterwards to sync new messages from server.
  messaging.loadCachedMessages(widget.conversationId);
  convs.openConversation(widget.conversationId);
  conn.socketService.getMessages(widget.conversationId, limit: 50);
});
```

- [ ] **Step 2: Update didUpdateWidget**

In `didUpdateWidget` (lines 136–141):

```dart
// BEFORE:
WidgetsBinding.instance.addPostFrameCallback((_) {
  final convs = context.read<ConversationsProvider>();
  final conn = context.read<ConnectionProvider>();
  convs.openConversation(widget.conversationId);
  conn.socketService.getMessages(widget.conversationId, limit: 50);
});

// AFTER:
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

- [ ] **Step 3: Verify _expandCacheForScroll behaviour**

Read `_onNewMessages` (lines 78–97) and confirm how `added` and `currentCount` are computed. Expected logic:

```dart
final isInitialLoad = added == currentCount && currentCount > 0;
```

When cache is pre-loaded: `added` = (new server messages only) ≠ `currentCount` (cache + new). So `isInitialLoad = false` → `_expandCacheForScroll` stays `false` → the expensive 10 000px cacheExtent rebuild is automatically skipped.

When no cache (first ever visit): `added == currentCount` → `isInitialLoad = true` → `_expandCacheForScroll = true` as before.

**If the first background sync still yields `added == currentCount`** (e.g. because `_lastMessageCount` was reset on screen mount), add an explicit guard:

```dart
// In _onNewMessages, change:
final isInitialLoad = added == currentCount && currentCount > 0;
// To:
final hasCached = context.read<MessagingProvider>().hasCachedMessages(widget.conversationId);
final isInitialLoad = !hasCached && added == currentCount && currentCount > 0;
```

Verify manually in the browser before committing.

- [ ] **Step 4: Run flutter analyze**

```bash
cd frontend && flutter analyze
```

Expected: no new warnings or errors.

- [ ] **Step 5: Manual test**

1. `docker-compose up`
2. `cd frontend && flutter run -d chrome`
3. Log in, open conversation A → wait for messages to fully load and decrypt
4. Press back → open conversation B → press back → open conversation A again
5. **Expected:** conversation A messages appear instantly (no empty-screen flash, no lag)
6. Wait 2–3 seconds → background sync completes quietly
7. Test disappearing messages: send a message in conversation A with 5s timer, wait for it to expire client-side, navigate away, come back → message must NOT reappear (server background sync removes it from `_messages` + cache via `onMessageHistory`)

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat(cache): use conversation cache for instant re-entry in ChatDetailScreen"
```

---

### Task 5: Final validation and CLAUDE.md update

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

- [ ] **Step 3: Update CLAUDE.md**

Add to the `### Frontend` Critical Rules section in `CLAUDE.md`:

```
- `_conversationCache` in MessagingProvider: per-conversation RAM cache (Map<int, List<MessageModel>>) for current session.
  Populated by `onMessageHistory` (first snapshot synchronously, second after decryption completes).
  Updated by all mutation handlers: `_handleIncomingMessage` (both plain and encrypted `.then()` paths),
  `_handleMessageDelivered`, `_handleMessageDeleted`. Cleared (remove entry) by `_handleChatHistoryCleared`,
  `onConversationDeleted`. Fully cleared by `clearAll()` (logout only).
  NOT cleared by `clearMessages()` (back navigation) or `onConnect` (socket reconnect).
  `loadCachedMessages(id)` returns bool — true means cache used, skip expensive scroll setup.
  `_effectiveActiveConversationId` getter: reads test override OR ConversationsProvider — use everywhere instead of inline `?? _conversationsProvider?.activeConversationId`.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document conversation message cache in CLAUDE.md"
```
