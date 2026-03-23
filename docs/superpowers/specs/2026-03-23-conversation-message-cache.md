# Spec: In-Session Conversation Message Cache

## Problem

Every time the user opens a chat screen (`ChatDetailScreen`), the app:
1. Fires `getMessages()` over the socket (network round-trip)
2. Replaces `_messages` with the server response
3. Triggers a full `notifyListeners()` → ListView rebuild with `cacheExtent = 10 000px`
4. Runs `_decryptMessageHistory` (even though SharedPreferences content cache is warm)

This causes a visible lag every time the user enters a conversation — even one they already visited in the same session.

Other encrypted messengers (Signal, Telegram) solve this by keeping a local source of truth and showing it instantly. We cannot change the server-as-source-of-truth architecture for history, but we can keep an in-RAM cache per conversation for the current session.

---

## Goal

Zero-lag re-entry into any previously-visited conversation during the same app session.

---

## Scope

- **In scope:** RAM cache in `MessagingProvider` for the current session only. Covers switching between conversations and navigating back/forward to the same chat.
- **Out of scope:** Persisting the message list across app restarts (Scenario B). The existing SharedPreferences cache for decrypted *content* (per message) is unchanged.

---

## Design

### New field in `MessagingProvider`

```dart
final Map<int, List<MessageModel>> _conversationCache = {};
```

Each entry: `conversationId → List<MessageModel>`. The cache is written twice per history load: immediately after parse/filter (may contain E2E placeholder strings for still-encrypted messages), then again after `_decryptMessageHistory` completes (fully decrypted content). On re-entry the user sees at worst a brief placeholder until the background sync runs; in practice the SharedPreferences content cache means decryption is near-instant.

### New public API

```dart
/// Returns true if cache was available and _messages was populated immediately.
bool loadCachedMessages(int conversationId)

/// Whether there is a warm cache for this conversation.
bool hasCachedMessages(int conversationId)
```

### Cache lifecycle

| Event | Action |
|---|---|
| `onMessageHistory()` received | After parse+filter: `_updateCache(id)`. After `_decryptMessageHistory` completes: `_updateCache(id)` again (decrypted content). |
| New message added to active conv (`_handleIncomingMessage`) | `_updateCache(activeConversationId)` |
| `_handleMessageDelivered()` | `_updateCache(conversationId)` — keeps delivery/read status current in cache |
| `_handleMessageDeleted()` | `_updateCache(conversationId)`; if list is now empty, `_conversationCache.remove(conversationId)` |
| `_handleChatHistoryCleared()` | `_conversationCache.remove(conversationId)` |
| `onConversationDeleted()` | `_conversationCache.remove(conversationId)` |
| `clearAll()` (logout) | `_conversationCache.clear()` |
| `clearMessages()` (back button) | **No change to cache** — this is the key change |

### ChatDetailScreen changes

In `initState` (and `didUpdateWidget`):

```dart
// Before firing getMessages, load from cache if available
messaging.loadCachedMessages(widget.conversationId); // returns bool, unused here
convs.openConversation(widget.conversationId);
conn.socketService.getMessages(widget.conversationId, limit: 50);
// _expandCacheForScroll only needed on true first load (no cache)
```

The `_onNewMessages` logic uses `isInitialLoad = (added == currentCount && currentCount > 0)` to trigger `_expandCacheForScroll = true`. When cache is pre-loaded, `added` will be small (only new messages from background sync), so `isInitialLoad` is false — **the expensive 10 000px cacheExtent rebuild is automatically skipped**. **Implementation note:** verify this assumption during Task 4 by checking how `added` and `currentCount` are computed in `_onNewMessages`; if the first server sync still sets `added == currentCount`, the cacheExtent optimization may not trigger automatically and will need an explicit guard.

### Background sync merge

When the background `getMessages()` response arrives via `onMessageHistory()`, it replaces `_messages` as today. This is fast because:
- Signal session is already advanced (history decryption runs, but SharedPreferences content cache hits immediately for known messages)
- The user sees cached messages instantly; the background replace is imperceptible if no new messages arrived

### Security

The RAM cache contains decrypted `MessageModel` objects — the same objects already in `_messages` for the active conversation. This is no different from the existing single-conversation `_messages` in RAM. It does not write anything additional to disk. The existing SharedPreferences content cache (per message, per key) is unchanged.

---

## Files Changed

| File | Change |
|---|---|
| `frontend/lib/providers/messaging_provider.dart` | Add `_conversationCache`, `loadCachedMessages()`, `hasCachedMessages()`, `_updateCache()`, `_effectiveActiveConversationId` getter. Update `onMessageHistory`, `_handleIncomingMessage` (both plain and encrypted `.then()` paths), `_handleMessageDelivered`, `_handleMessageDeleted`, `_handleChatHistoryCleared`, `onConversationDeleted`, `clearAll`. Leave `clearMessages()` and `onConnect` unchanged (neither touches cache). |
| `frontend/lib/screens/chat_detail_screen.dart` | Call `loadCachedMessages()` before `getMessages()` in `initState` and `didUpdateWidget`. |
| `frontend/test/providers/messaging_provider_cache_test.dart` | New test file: cache lifecycle unit tests. |
