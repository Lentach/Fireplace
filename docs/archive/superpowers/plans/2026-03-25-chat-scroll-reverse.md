# Chat Scroll `reverse: true` Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the forward `ListView` scroll architecture with `reverse: true` so that `pixels = 0` is always the visual bottom (newest message), eliminating the root cause of mobile-web scroll jitter.

**Architecture:** `MessagingProvider._messages` stays oldest-first; only the display layer flips the index with `msgIndex = messages.length - 1 - index`. All scroll-to-bottom calls become `animateTo(0)`. The `_expandCacheForScroll` hack, `ScrollMetricsNotification` handler, `RefreshIndicator`, and three cache-related fields are deleted.

**Tech Stack:** Flutter 3.x, `ScrollController`, `NotificationListener<UserScrollNotification>`, `SchedulerBinding.addPostFrameCallback`.

**Spec:** `docs/superpowers/specs/2026-03-25-chat-scroll-reverse-design.md`

---

## File Map

| File | What changes |
|---|---|
| `frontend/lib/screens/chat_detail_screen.dart` | All scroll logic — ~−80/+40 lines |
| `CLAUDE.md` | Update ChatDetailScreen scroll description |

`frontend/lib/providers/messaging_provider.dart` — **no changes**.

---

## Task 1: Flip `_onScroll` scroll direction

**File:** `frontend/lib/screens/chat_detail_screen.dart:64-87`

The `_onScroll` listener controls three things: (1) `_wasNearBottom` / `_userHasScrolledChat`, (2) `_showScrollToBottomButton`, (3) pagination trigger. All three need the direction flip.

- [ ] **Step 1.1 — Replace `_onScroll` body**

  Find the current `_onScroll` method (lines 64–87) and replace it entirely:

  ```dart
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // With reverse:true, pixels=0 is the bottom (newest). Near-bottom = pixels <= threshold.
    final atBottom = pos.pixels <= _scrollToBottomThreshold;
    _wasNearBottom = atBottom;
    if (atBottom) {
      _userHasScrolledChat = false;
    }
    // NOTE: do NOT write _lastMaxScrollExtent here — that field is deleted in Task 5
    // (it was only read by _onScrollMetricsNotification which is deleted in Task 3).
    if (_showScrollToBottomButton != !atBottom && mounted) {
      setState(() => _showScrollToBottomButton = !atBottom);
    }

    // Near visual top (oldest messages) = pixels near maxScrollExtent → load older.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      final messaging = context.read<MessagingProvider>();
      if (!messaging.isLoadingMore && messaging.hasMoreMessages) {
        _prePaginationScrollOffset = _scrollController.offset;
        _prePaginationScrollExtent = _scrollController.position.maxScrollExtent;
        setState(() => _isLoadingMoreLocal = true);
        messaging.loadOlderMessages(widget.conversationId);
      }
    }
  }
  ```

- [ ] **Step 1.2 — Run `flutter analyze`**

  ```bash
  cd frontend && flutter analyze
  ```

  Expected: no errors (logic change only, no API changes).

- [ ] **Step 1.3 — Commit**

  ```bash
  git add frontend/lib/screens/chat_detail_screen.dart
  git commit -m "refactor(chat-scroll): flip _onScroll direction for reverse:true"
  ```

---

## Task 2: Simplify `_scrollToBottom` and `_onScrollToBottomButtonTap`

**File:** `frontend/lib/screens/chat_detail_screen.dart:238-269`

`_scrollToBottom` currently targets `maxScrollExtent` with a 200ms delay and a cache-shrink `.then()`. With `reverse: true` the target is `0` and the delay/cache logic are gone. `_onScrollToBottomButtonTap` had a `_expandCacheForScroll` set that also goes away.

- [ ] **Step 2.1 — Replace `_scrollToBottom`**

  Replace the entire `_scrollToBottom` method (lines 238–261):

  ```dart
  void _scrollToBottom() {
    if (mounted) setState(() => _newMessagesCount = 0);
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }
  ```

- [ ] **Step 2.2 — Replace `_onScrollToBottomButtonTap`**

  Replace the entire `_onScrollToBottomButtonTap` method (lines 263–269):

  ```dart
  void _onScrollToBottomButtonTap() {
    _scrollToBottom();
  }
  ```

- [ ] **Step 2.3 — Run `flutter analyze`**

  ```bash
  cd frontend && flutter analyze
  ```

  Expected: no errors. The `_expandCacheForScroll` field still exists (it will be removed in Task 5), but it will now be written only in `_onNewMessages` — that's fine temporarily.

- [ ] **Step 2.4 — Commit**

  ```bash
  git add frontend/lib/screens/chat_detail_screen.dart
  git commit -m "refactor(chat-scroll): _scrollToBottom targets 0, remove delay and cache shrink"
  ```

---

## Task 3: `ListView` — `reverse: true` + `itemBuilder` flip

**File:** `frontend/lib/screens/chat_detail_screen.dart:551-592`

This is the core visual change. Three changes in one block: add `reverse: true`, replace the two `NotificationListener` wrappers with a single `NotificationListener<UserScrollNotification>`, and fix `itemBuilder` (spinner position + index flip).

- [ ] **Step 3.1 — Replace the entire `NotificationListener` tree + `ListView`**

  Find the block starting with `NotificationListener<ScrollNotification>` (line 551) through the closing `),` of the outer listener (line 592). Replace it with:

  ```dart
  NotificationListener<UserScrollNotification>(
    onNotification: (notification) {
      _userHasScrolledChat = true;
      return false;
    },
    child: ListView.builder(
      reverse: true,
      controller: _scrollController,
      padding: const EdgeInsets.only(
        left: 16,
        right: 20,
        top: 8,
        bottom: 8,
      ),
      itemCount: messages.length + (_isLoadingMoreLocal ? 1 : 0),
      itemBuilder: (context, index) {
        // Spinner at visual top (highest index = last rendered item with reverse:true).
        // Check BEFORE the flip so message indices are unaffected.
        if (_isLoadingMoreLocal && index == messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        // Flip: _messages is oldest-first; index 0 renders at visual bottom (newest).
        final msgIndex = messages.length - 1 - index;
        final msg = messages[msgIndex];
        // Date separator condition unchanged — still correct after flip.
        // msgIndex==0 is the globally oldest (visual top); isDifferentDay catches day
        // boundaries in chronological order. See spec for proof.
        final showDate = msgIndex == 0 ||
            _isDifferentDay(
              messages[msgIndex - 1].createdAt,
              msg.createdAt,
            );
        return Column(
          children: [
            if (showDate) MessageDateSeparator(date: msg.createdAt),
            if (showDate) const SizedBox(height: 8),
            ChatMessageBubble(
              message: msg,
              isMine: msg.senderId == auth.currentUser!.id,
            ),
          ],
        );
      },
    ),
  ),
  ```

  Also delete the now-unused `_onScrollMetricsNotification` and `_onScrollInteractionNotification` methods (lines 90–110).

- [ ] **Step 3.2 — Run `flutter analyze`**

  ```bash
  cd frontend && flutter analyze
  ```

  Expected: no errors.

- [ ] **Step 3.3 — Quick smoke test (visual)**

  Start the app (`flutter run -d chrome`), open any chat. Verify:
  - Newest message is visible at the bottom on open.
  - Scrolling up shows older messages at the top.
  - Date chips appear above the correct day groups.

- [ ] **Step 3.4 — Commit**

  ```bash
  git add frontend/lib/screens/chat_detail_screen.dart
  git commit -m "refactor(chat-scroll): reverse:true, itemBuilder index flip, UserScrollNotification"
  ```

---

## Task 4: Simplify `_onNewMessages`

**File:** `frontend/lib/screens/chat_detail_screen.dart:112-166`

The current `_onNewMessages` has a cache-expansion block for the initial snapshot. Replace it with the two sub-cases from the spec: (a) initial snapshot → sync `_lastMessageCount` only; (b) subsequent → `_wasNearBottom` gate or badge.

The `_isLoadingMoreLocal` pagination branch at the top of the method **stays unchanged**.

- [ ] **Step 4.1 — Replace `_onNewMessages` non-pagination path**

  The pagination branch occupies lines 113–140. Leave it untouched. Replace lines 141–166 (everything after `return;` that closes the pagination branch):

  ```dart
    // Non-pagination path.
    if (added <= 0) return;

    // Initial full snapshot: opening the chat. _lastMessageCount was 0 so added == currentCount.
    // Do NOT badge — this is the open render, not an incoming message.
    // pixels=0 already shows newest with reverse:true; no explicit scroll needed.
    if (_lastMessageCount == 0 && added == currentCount) {
      _lastMessageCount = currentCount;
      final messaging = context.read<MessagingProvider>();
      _lastLinkPreviewCount =
          messaging.messages.where((m) => m.linkPreviewUrl != null).length;
      return;
    }

    // Subsequent incoming message.
    _lastMessageCount = currentCount;
    final messaging = context.read<MessagingProvider>();
    _lastLinkPreviewCount =
        messaging.messages.where((m) => m.linkPreviewUrl != null).length;
    if (_wasNearBottom && !_userHasScrolledChat) {
      _scrollToBottom();
    } else {
      setState(() => _newMessagesCount++);
    }
  }
  ```

- [ ] **Step 4.2 — Run `flutter analyze`**

  ```bash
  cd frontend && flutter analyze
  ```

- [ ] **Step 4.3 — Test: no false badge on open**

  Open a chat with ≥5 messages. Verify the scroll-to-bottom badge counter does **not** appear on open (it should only appear when a message arrives while reading history).

- [ ] **Step 4.4 — Commit**

  ```bash
  git add frontend/lib/screens/chat_detail_screen.dart
  git commit -m "refactor(chat-scroll): simplify _onNewMessages — initial snapshot guard, wasNearBottom badge gate"
  ```

---

## Task 5: Remove dead fields and constants

**File:** `frontend/lib/screens/chat_detail_screen.dart:47-62`

Four fields/constants are now dead: `_expandCacheForScroll`, `_openedWithWarmMessageCache`, `_largeCacheExtent`, `_warmCacheExpandMessageThreshold`. Also remove their last write sites and the `_lastMaxScrollExtent` field (only used by the deleted `_onScrollMetricsNotification`).

- [ ] **Step 5.1 — Remove field declarations**

  Delete lines 47–62 (the five declarations and their doc comments):
  ```dart
  // DELETE these lines:
  bool _expandCacheForScroll = false;
  bool _openedWithWarmMessageCache = false;
  static const double _largeCacheExtent = 10000;
  static const int _warmCacheExpandMessageThreshold = 15;
  double _lastMaxScrollExtent = 0;
  ```

  Also delete the `double _lastMaxScrollExtent = 0;` field declaration. Task 1 intentionally omitted writing this field in the new `_onScroll` body (it was only read by `_onScrollMetricsNotification`, which is deleted in Task 3). So by this point the field is already write-free; just remove the declaration.

- [ ] **Step 5.2 — Remove `_openedWithWarmMessageCache` write sites in `initState` and `didUpdateWidget`**

  In `initState` (around line 176):
  ```dart
  // DELETE:
  _openedWithWarmMessageCache =
      messaging.loadCachedMessages(widget.conversationId);
  // KEEP the loadCachedMessages call (cache still needed), just not the assignment:
  messaging.loadCachedMessages(widget.conversationId);
  ```

  Repeat for the matching lines in `didUpdateWidget` (around line 207–213). Remove the `_openedWithWarmMessageCache = false;` reset and the assignment inside the callback.

- [ ] **Step 5.3 — Run `flutter analyze`**

  ```bash
  cd frontend && flutter analyze
  ```

  Expected: no errors. If analyze reports unused variable/field warnings they should all be from the items we're deleting.

- [ ] **Step 5.4 — Run `flutter test`**

  ```bash
  cd frontend && flutter test
  ```

  Expected: all 79 tests pass.

- [ ] **Step 5.5 — Commit**

  ```bash
  git add frontend/lib/screens/chat_detail_screen.dart
  git commit -m "refactor(chat-scroll): remove dead fields _expandCacheForScroll, _openedWithWarmMessageCache, _largeCacheExtent, _warmCacheExpandMessageThreshold"
  ```

---

## Task 6: Remove `RefreshIndicator` + fix keyboard scroll

**File:** `frontend/lib/screens/chat_detail_screen.dart`

Two independent cleanups: (1) `RefreshIndicator` wraps the list at the wrong overscroll edge after `reverse: true`; remove it and simplify the empty-state widget. (2) Keyboard scroll targets `maxScrollExtent` — flip to `0` and remove the now-pointless `if (maxExtent > 0)` guard.

- [ ] **Step 6.1 — Remove `RefreshIndicator`, simplify empty state**

  After Task 3 the file has this structure inside `ChatBackgroundPattern`:
  ```dart
  child: RefreshIndicator(
    onRefresh: () async { ... },
    child: messages.isEmpty
      ? LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: Center(child: Text(...noMessagesYet...)),
            ),
          ),
        )
      : NotificationListener<UserScrollNotification>(...ListView.builder...),
  ),
  ```

  Make **two targeted edits** (do not touch the `NotificationListener` / `ListView.builder` subtree):

  **Edit A** — Remove the `RefreshIndicator(onRefresh: ..., child:` opening and its matching `),` closing. The `child:` of `ChatBackgroundPattern` becomes the ternary directly.

  **Edit B** — Replace the empty-state branch:
  ```dart
  // BEFORE (the LayoutBuilder/SingleChildScrollView/SizedBox tree):
  LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: constraints.maxHeight,
        child: Center(
          child: Text(
            AppLocalizations.of(context).noMessagesYet,
            style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
          ),
        ),
      ),
    ),
  )

  // AFTER:
  Center(
    child: Text(
      AppLocalizations.of(context).noMessagesYet,
      style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
    ),
  )
  ```

  The `NotificationListener<UserScrollNotification>(...ListView.builder...)` is untouched.

- [ ] **Step 6.2 — Fix keyboard scroll**

  Find the keyboard scroll block (around lines 452–469):
  ```dart
  if (keyboardHeight > 0 && _lastKeyboardHeight == 0 && messages.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted || !_scrollController.hasClients) return;
        final maxExtent = _scrollController.position.maxScrollExtent;
        if (maxExtent > 0) {
          _scrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }
  ```

  Replace with:
  ```dart
  if (keyboardHeight > 0 && _lastKeyboardHeight == 0 && messages.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    });
  }
  ```

- [ ] **Step 6.3 — Run `flutter analyze`**

  ```bash
  cd frontend && flutter analyze
  ```

  Expected: clean.

- [ ] **Step 6.4 — Run `flutter test`**

  ```bash
  cd frontend && flutter test
  ```

  Expected: all 79 tests pass.

- [ ] **Step 6.5 — Commit**

  ```bash
  git add frontend/lib/screens/chat_detail_screen.dart
  git commit -m "refactor(chat-scroll): remove RefreshIndicator, simplify empty state, fix keyboard scroll target"
  ```

---

## Task 7: Update `CLAUDE.md`

**File:** `CLAUDE.md` — the `_conversationCache` / ChatDetailScreen section under `## 1. Critical Rules & Gotchas / Frontend`.

- [ ] **Step 7.1 — Update the scroll description**

  Find the paragraph starting with `` `_openedWithWarmMessageCache` still uses a large `cacheExtent` `` in the `_conversationCache` description. Replace the entire tail of that paragraph (everything about warm cache, cacheExtent, ScrollMetricsNotification, UserScrollNotification, `_openedWithWarmMessageCache`, `_warmCacheExpandMessageThreshold`) with:

  ```
  `ChatDetailScreen` uses `ListView(reverse: true)`: `pixels = 0` is the visual bottom (newest message), eliminating the need to chase `maxScrollExtent`. `jumpTo(0)` / `animateTo(0)` are always correct regardless of lazy build state. `_userHasScrolledChat` (set by `NotificationListener<UserScrollNotification>`) suppresses auto-scroll-to-bottom while the user reads history; cleared when `pixels <= _scrollToBottomThreshold` in `_onScroll`. Pagination trigger: `pixels >= maxScrollExtent - 300` (near visual top). `loadCachedMessages(id)` returns bool — true when RAM cache was applied.
  ```

- [ ] **Step 7.2 — Remove references to deleted fields**

  Search CLAUDE.md for any remaining mentions of:
  - `_expandCacheForScroll`
  - `_openedWithWarmMessageCache`
  - `_warmCacheExpandMessageThreshold`
  - `_largeCacheExtent`
  - `ScrollMetricsNotification` (in the ChatDetailScreen context)

  Delete or reword each one.

- [ ] **Step 7.3 — Commit**

  ```bash
  git add CLAUDE.md
  git commit -m "docs(claude-md): update ChatDetailScreen scroll section for reverse:true refactor"
  ```

---

## Task 8: Final verification

- [ ] **Step 8.1 — Full analyze + test**

  ```bash
  cd frontend && flutter analyze && flutter test
  ```

  Expected: no analyzer issues, all 79 tests pass.

- [ ] **Step 8.2 — Manual: long thread (≥15 messages)**

  ```
  flutter run -d chrome
  ```

  Open a chat with ≥15 messages. Verify:
  - [ ] Newest message is visible at bottom immediately on open (no jitter, no scroll needed).
  - [ ] Scroll up to read older messages — no involuntary snap back to bottom.
  - [ ] While reading history, send a message from the other user → badge counter appears, no auto-scroll.
  - [ ] Tap the badge → `animateTo(0)` → newest message visible, badge clears.
  - [ ] Scroll to visual top → spinner appears → older messages load → scroll position preserved.
  - [ ] Date chips appear correctly above the oldest message of each day.

- [ ] **Step 8.3 — Manual: short thread (<15 messages)**

  - [ ] Opens correctly, no jitter, no badge on initial open.

- [ ] **Step 8.4 — Manual: keyboard focus regression**

  - [ ] Type and send a message rapidly with the keyboard open.
  - [ ] Soft keyboard stays visible and focused after send (removal of 200ms delay must not regress this).
  - [ ] If keyboard closes unexpectedly: re-add a small delay (50–100ms) and note in commit message.

- [ ] **Step 8.5 — Manual: mobile web touch (phone on same Wi-Fi)**

  ```bash
  cd frontend && .\run_web_for_phone.ps1
  ```

  - [ ] Drag the list up (towards older messages) — `_userHasScrolledChat` must be set; no auto-snap.
  - [ ] Scroll back to bottom — `_userHasScrolledChat` clears; next new message auto-scrolls.

- [ ] **Step 8.6 — Manual: image-at-bottom stability**

  Open a chat where the last message contains an image.
  - [ ] List stays at visual bottom while image renders — no jump, no jitter.

- [ ] **Step 8.7 — Commit verification note**

  ```bash
  git add .
  git commit -m "test(chat-scroll): manual verification passed — reverse:true stable on web and mobile web"
  ```

---

## Summary of Commits

| Task | Commit message |
|---|---|
| 1 | `refactor(chat-scroll): flip _onScroll direction for reverse:true` |
| 2 | `refactor(chat-scroll): _scrollToBottom targets 0, remove delay and cache shrink` |
| 3 | `refactor(chat-scroll): reverse:true, itemBuilder index flip, UserScrollNotification` |
| 4 | `refactor(chat-scroll): simplify _onNewMessages — initial snapshot guard, wasNearBottom badge gate` |
| 5 | `refactor(chat-scroll): remove dead fields _expandCacheForScroll, _openedWithWarmMessageCache, _largeCacheExtent, _warmCacheExpandMessageThreshold` |
| 6 | `refactor(chat-scroll): remove RefreshIndicator, simplify empty state, fix keyboard scroll target` |
| 7 | `docs(claude-md): update ChatDetailScreen scroll section for reverse:true refactor` |
| 8 | `test(chat-scroll): manual verification passed` |
