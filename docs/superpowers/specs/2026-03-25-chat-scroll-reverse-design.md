# Chat Scroll: `reverse: true` Refactor

**Date:** 2026-03-25
**Status:** Approved
**Scope:** `frontend/lib/screens/chat_detail_screen.dart` + `CLAUDE.md`

---

## Problem

The current `ListView.builder` (forward direction) renders newest messages at the bottom by chasing
`maxScrollExtent` — a value that grows as the lazy list builds items, images load, and E2E decryption
fills in content. This causes:

- Scroll-to-bottom fights `ScrollMetricsNotification` during lazy layout growth (mobile web jitter).
- The `_expandCacheForScroll` hack forces a full pre-build before `jumpTo(maxScrollExtent)` is safe.
- Five independent code paths all call scroll-to-bottom with no central authority.
- User reading history gets involuntarily dragged back toward the newest message.

---

## Solution

Switch `ListView.builder` to `reverse: true`. Position 0 is always the bottom (newest message).
`jumpTo(0)` is unconditionally correct regardless of list height, lazy build state, or image loading.

### Industry precedent

WhatsApp, Telegram, Signal (Android `RecyclerView`), iMessage, and every major Flutter chat library
(`flutter_chat_ui`, `scrollview_observer`) all use a reversed list for exactly this reason.

---

## Architecture

### Data ordering — unchanged

`MessagingProvider._messages` stays **oldest-first**. The provider contract, cache, pagination, and
E2E decrypt flow are untouched. Only the display layer flips the index.

### Index flip in `itemBuilder`

```dart
// itemCount: messages.length + (_isLoadingMoreLocal ? 1 : 0)
//
// Spinner check BEFORE the flip so message indices are unaffected.
if (_isLoadingMoreLocal && index == messages.length) {
  return /* CircularProgressIndicator */;
}
final msgIndex = messages.length - 1 - index;  // flip
final msg = messages[msgIndex];
// Date separator: condition UNCHANGED.
//   showDate = (msgIndex == 0) || isDifferentDay(messages[msgIndex-1], msg)
// With _messages oldest-first and reverse:true this is still correct:
//   index n-1 → msgIndex=0 (oldest, visual top) → showDate=true ✓
//   Tue_1 maps to msgIndex where messages[msgIndex-1] is last Mon msg → fires ✓
```

### Scroll coordinate system

| Concept | Before | After |
|---|---|---|
| Bottom (newest) | `maxScrollExtent` (moving) | `0` (fixed) |
| Top (oldest) | `0` | `maxScrollExtent` |
| Scroll-to-bottom | `animateTo(maxScrollExtent)` | `animateTo(0)` |
| "Near bottom" test | `pixels >= maxScrollExtent - threshold` | `pixels <= threshold` |
| Pagination trigger | `pixels <= minScrollExtent + 300` | `pixels >= maxScrollExtent - 300` |

---

## Component Changes

### `chat_detail_screen.dart`

#### Add
- `reverse: true` on `ListView.builder`
- Index flip: `msgIndex = messages.length - 1 - index`
- Spinner condition: `index == messages.length` (visual top)
- `_onScroll` near-bottom: `pixels <= _scrollToBottomThreshold`
- Pagination trigger: `pixels >= maxScrollExtent - 300`
- `_scrollToBottom`: `animateTo(0, ...)`
- Keyboard scroll: `animateTo(0, ...)`

#### Remove
- `_expandCacheForScroll` flag and all write sites
- `_largeCacheExtent` constant
- `_openedWithWarmMessageCache` flag
- `_warmCacheExpandMessageThreshold` constant
- `NotificationListener<ScrollMetricsNotification>` wrapper and `_onScrollMetricsNotification` method
- `NotificationListener<ScrollNotification>` outer wrapper and `_onScrollInteractionNotification` method
- `RefreshIndicator` — with `reverse: true` the overscroll edge that triggers it is the visual bottom
  (newest-message end), which is the wrong end for a "reload" gesture. Pagination via scroll-to-top
  replaces it.
- Double `addPostFrameCallback` cache-expansion block in `_onNewMessages`
- `isFullSnapshotFirstPaint` / `shouldExpandCacheForInitialScroll` logic in `_onNewMessages`

#### Add / Replace
- `NotificationListener<UserScrollNotification>` (narrower) wrapping only the `ListView`, setting
  `_userHasScrolledChat = true` inline. This replaces the removed `ScrollNotification` wrapper and
  preserves the guard against auto-scroll while the user reads history.

#### Simplify
- `_onNewMessages` — **keep the `_isLoadingMoreLocal` pagination branch unchanged** (the
  `postFrameCallback` that calls `jumpTo(preOffset + delta)` must stay). Only remove the
  cache-expansion block (`isFullSnapshotFirstPaint` / `shouldExpandCacheForInitialScroll`).
  For non-pagination new messages: if `_wasNearBottom && !_userHasScrolledChat` → `_scrollToBottom()`;
  else increment `_newMessagesCount`. Initial full snapshot no longer needs explicit scroll (list
  opens at `pixels = 0` by default with `reverse: true`).
- `_userHasScrolledChat`: keep — still suppresses auto-scroll when user reads history. Set by the
  new `NotificationListener<UserScrollNotification>` wrapper; cleared when `pixels <= threshold`
  in `_onScroll`.

### `messaging_provider.dart` — no changes

### `CLAUDE.md`
- Update ChatDetailScreen / `_conversationCache` section: document `reverse: true`, remove references
  to `_expandCacheForScroll`, `_openedWithWarmMessageCache`, `_warmCacheExpandMessageThreshold`.

---

## Edge Cases

| Case | Behavior |
|---|---|
| Cold open (no cache) | List renders with `pixels = 0` = newest visible. No scroll needed. |
| Warm cache open | Same — already at bottom. `_openedWithWarmMessageCache` path deleted. |
| New message, user at bottom | `_wasNearBottom` true → `animateTo(0)` (instant, already there) |
| New message, user reading history | `_userHasScrolledChat` true → badge increments, no scroll |
| Load older messages | Spinner at `index == messages.length` (visual top). Scroll math `preOffset + (newExtent - preExtent)` unchanged and still correct. |
| Keyboard opens | `animateTo(0)` — same intent, simpler |
| Link preview arrives | Same: count-change path → `_scrollToBottom()` if atBottom |
| Short thread (<15 msgs) | No special path — `_warmCacheExpandMessageThreshold` branch deleted |
| Pull-to-refresh gesture | `RefreshIndicator` removed; reload available via `getMessages` on reconnect or app resume |
| `didUpdateWidget` (conversation switch) | Reset `_userHasScrolledChat`; no cache flags to reset |

---

## Pagination Scroll Math

With `reverse: true`, `pixels = 0` is the bottom. When older messages are prepended to `_messages`
(visually appearing at the top), `maxScrollExtent` grows by `delta = newExtent - preExtent`. The user's
viewing position is preserved by:

```dart
_scrollController.jumpTo(preOffset + (newExtent - preExtent));
```

This math is unchanged from the current implementation and remains correct.

---

## Testing

- `flutter analyze` — must pass clean.
- `flutter test` — all 79 tests must pass; update any widget tests that assert scroll direction or
  message index order in `ChatDetailScreen`.
- Manual: web on phone — open chat ≥15 messages, scroll up to history, new message arrives (badge
  shows, no auto-jump), tap badge → `animateTo(0)` lands at newest. Paginate: scroll to visual top,
  spinner appears, older messages prepend, position preserved.
- Manual: short thread (<15 msgs) — opens correctly, no jitter.

---

## Files Touched

| File | Change |
|---|---|
| `frontend/lib/screens/chat_detail_screen.dart` | ~−80 / +40 lines (mostly deletions) |
| `CLAUDE.md` | Update scroll section |
| Widget tests for `ChatDetailScreen` | Update scroll direction assertions |
