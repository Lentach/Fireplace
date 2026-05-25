# PWA App Badge (Badging API) Implementation Plan

> **For agentic workers:** Implement task-by-task; checkboxes optional for tracking.

**Goal:** Sync the installed PWA app icon badge to the sum of conversation unread counts (capped at 19), clearing when zero, web-only via Badging API bridge.

**Architecture:** Pure Dart helpers for sum + cap; conditional-import `BadgingBridge` (stub vs `dart:js_util` web); `UnreadBadgeSync` listens to `ConversationsProvider` with debounce and applies/clears badge; wired from `MainShell` (logged-in shell), disposed on logout navigation.

**Tech stack:** Flutter 3.x, `dart:js_util` on web, `provider`.

**Naming (vs design spec):** The approved spec used placeholder names `AppBadgeBridge` / `applyUnreadTotal`. The implementation uses `BadgingBridge`, `setBadgeCount(int)` for non-zero capped totals, and `clearBadge()` — same behavior as the spec’s apply/clear split.

**Logout / not logged in:** Badge is cleared in `UnreadBadgeSync.dispose()`, called from `MainShell.dispose()`. On logout, `AuthGate` replaces the logged-in tree, so `MainShell` unmounts and the badge clears. No separate `AuthProvider` hook is required unless navigation is refactored to keep `MainShell` mounted while logged out.

---

## Implementation status

**Completed:** 2026-05-10 (see `frontend/lib/utils/app_badge_math.dart`, `frontend/lib/services/badging_bridge_*.dart`, `frontend/lib/services/unread_badge_sync.dart`, `frontend/lib/screens/main_shell.dart`, `frontend/test/utils/app_badge_math_test.dart`; `CLAUDE.md` § Frontend PWA badge).

Re-run **Task 6** after any change to these paths.

---

### Task 1: Math helpers + unit tests

**Files:**
- Create: `frontend/lib/utils/app_badge_math.dart`
- Create: `frontend/test/utils/app_badge_math_test.dart`

- [x] Add `sumUnreadBadgeCounts(Map<int, int>)` and `capUnreadForBadge(int totalUnread)` per spec.
- [x] Unit tests for sums, cap at 19, zero edge cases.

---

### Task 2: Badging bridge (stub + web)

**Files:**
- Create: `frontend/lib/services/badging_bridge_stub.dart`
- Create: `frontend/lib/services/badging_bridge_web.dart`

- [x] Shared API: `isSupported`, `setBadgeCount(int)` (non-zero), `clearBadge()`, factory `createBadgingBridge()`.
- [x] Web: feature-detect `setAppBadge` / `clearAppBadge`, `promiseToFuture`, swallow errors.

---

### Task 3: UnreadBadgeSync

**Files:**
- Create: `frontend/lib/services/unread_badge_sync.dart`

- [x] Constructor takes `ConversationsProvider`, optional `Duration debounce` (~200 ms).
- [x] `addListener` → debounced recompute from `unreadCounts`; skip duplicate capped sends.
- [x] `dispose()`: remove listener, cancel timer, `clearBadge()`.

---

### Task 4: Wire MainShell

**Files:**
- Modify: `frontend/lib/screens/main_shell.dart`

- [x] Field `UnreadBadgeSync? _unreadBadgeSync`; start in `addPostFrameCallback` when `kIsWeb` (after `mounted`, read `ConversationsProvider`).
- [x] `dispose()`: `_unreadBadgeSync?.dispose()` (async cleanup via `unawaited`).

---

### Task 5: Docs + graphify

**Files:**
- Modify: `CLAUDE.md` (PWA / Web Push section: Badging API, iOS Home Screen caveat)
- Run: `graphify update .`

- [x] Documented in `CLAUDE.md`.
- [x] `graphify update .` (re-run after implementation file edits per workspace rule).

---

### Task 6: Verification

- [ ] `flutter analyze` — re-run when changing badge code; local runs may still flag `dart:js_util` / web-only imports when the analyzer target is not web (CI uses the standard Flutter toolchain).
- [x] `flutter test` (passed 2026-05-10).
