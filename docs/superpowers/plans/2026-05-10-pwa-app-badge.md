# PWA App Badge (Badging API) Implementation Plan

> **For agentic workers:** Implement task-by-task; checkboxes optional for tracking.

**Goal:** Sync the installed PWA app icon badge to the sum of conversation unread counts (capped at 19), clearing when zero, web-only via Badging API bridge.

**Architecture:** Pure Dart helpers for sum + cap; conditional-import `BadgingBridge` (stub vs `dart:js_util` web); `UnreadBadgeSync` listens to `ConversationsProvider` with debounce and applies/clears badge; wired from `MainShell` (logged-in shell), disposed on logout navigation.

**Tech stack:** Flutter 3.x, `dart:js_util` on web, `provider`.

---

### Task 1: Math helpers + unit tests

**Files:**
- Create: `frontend/lib/utils/app_badge_math.dart`
- Create: `frontend/test/utils/app_badge_math_test.dart`

- [ ] Add `sumUnreadBadgeCounts(Map<int, int>)` and `capUnreadForBadge(int totalUnread)` per spec.
- [ ] Unit tests for sums, cap at 19, zero edge cases.

---

### Task 2: Badging bridge (stub + web)

**Files:**
- Create: `frontend/lib/services/badging_bridge_stub.dart`
- Create: `frontend/lib/services/badging_bridge_web.dart`

- [ ] Shared API: `isSupported`, `setBadgeCount(int)` (non-zero), `clearBadge()`, factory `createBadgingBridge()`.
- [ ] Web: feature-detect `setAppBadge` / `clearAppBadge`, `promiseToFuture`, swallow errors.

---

### Task 3: UnreadBadgeSync

**Files:**
- Create: `frontend/lib/services/unread_badge_sync.dart`

- [ ] Constructor takes `ConversationsProvider`, optional `Duration debounce` (~200 ms).
- [ ] `addListener` → debounced recompute from `unreadCounts`; skip duplicate capped sends.
- [ ] `dispose()`: remove listener, cancel timer, `clearBadge()`.

---

### Task 4: Wire MainShell

**Files:**
- Modify: `frontend/lib/screens/main_shell.dart`

- [ ] Field `UnreadBadgeSync? _unreadBadgeSync`; start in `addPostFrameCallback` when `kIsWeb` (after `mounted`, read `ConversationsProvider`).
- [ ] `dispose()`: `_unreadBadgeSync?.dispose()`.

---

### Task 5: Docs + graphify

**Files:**
- Modify: `CLAUDE.md` (PWA / Web Push section: Badging API, iOS Home Screen caveat)
- Run: `graphify update .`

---

### Task 6: Verification

- [ ] `flutter analyze` on touched paths
- [ ] `flutter test`
