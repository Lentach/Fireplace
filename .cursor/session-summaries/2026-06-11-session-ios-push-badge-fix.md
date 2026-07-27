# iOS PWA notifications + badge: post-mortem and unified fix (2nd attempt)

**Date:** 2026-06-11

## What was done

Post-mortem of the prior push/badge fix (PR #4, `d0b9bbb`) against verified-broken behavior on iOS Safari PWA, then a unified fix. Prod was confirmed at HEAD (`/version` → 0.0.48 @ faf5c34; deployed `web-push-sw.js` byte-matched source), so all failures were code bugs, not stale deploys.

**Root causes found (code-cited):**
1. **Stacking (Bug 1):** tag `conversation-<id>` was stable and correct, but iOS WebKit has never implemented tag replacement (WebKit bug 258922, open since 2023) — every `showNotification` stacks. Additionally ALL app-side tray sweeps + badge messages were dead: `notification_cleaner_web.dart` used `serviceWorker.ready`/`.controller`, which resolve the **Flutter app SW at scope `/`**, never the push SW at `/web-push-scope/`.
2. **Deep-link (Bug 2):** (a) `WebPushBridge.listenForNotificationClicks` used `addEventListener('message')` without `navigator.serviceWorker.startMessages()` — per spec WebKit queues client messages forever, so the SW's click postMessage never arrived (app focused on whatever tab was open); (b) killed-PWA cold start: iOS opens the PWA at manifest `start_url`, dropping `clients.openWindow('/?notify_conv=')`.
3. **Badge (Bug 4):** SW already wrote the live `unreadTotal` (backend computes at coalescing flush) — but (a) all app-context clears went to the wrong SW (dead, see 1), (b) `UnreadBadgeSync._flush` refused to clear when `_lastSentCapped == null`, i.e. it never cleared a badge the SW wrote → permanently stale counts; "reset to 1" was the true total being written after a missing clear, plus a real fallback path (`unreadTotal` absent → `unreadCount` → 1) when the unread summary query failed at flush.
4. The reported 5→8 duplicate-delivery clue was withdrawn by the user (notification count always matches messages); backend coalescing + per-endpoint upsert verified sound anyway.

**Fix (frontend-only; backend payload unchanged, no sender name by user choice):**
- `web-push-sw.js`: `closeNotificationsForTag(tag)` before `showNotification` (emulates tag replace on iOS); `renotify: true`; badge write **skipped** when `payload.unreadTotal` absent; `notificationclick` derives convId from the tag when `data` is missing, closes the whole tag group, persists `{conversationId, at}` to IndexedDB (`fireplace-push`/`kv`/`pending-deep-link`) before focusing/postMessage/openWindow; new message types `close-conv` + `sweep` so tray ops run in SW context.
- New `PushSwChannel` (`services/push_sw_channel_{stub,web}.dart`): the ONLY correct way to reach the push SW — `getRegistration('/web-push-scope/')` → `reg.active.postMessage`.
- `NotificationCleaner` (web) now posts `close-conv`/`sweep` via the channel; window Badging API only as no-push-SW fallback.
- `WebPushBridge`: `startMessages()` after listener registration.
- New `utils/pending_deep_link_{stub,web}.dart`: read+delete IndexedDB record (5-min TTL); drained in `main()` (cold start), `MainShell` tab-visible (suspended-resume), cleared by `PushService` click handler when the live path handled the tap.
- `UnreadBadgeSync`: single-writer routing via `PushSwChannel` (bridge fallback); gates on new `ConversationsProvider.hasLoadedConversationsOnce` (no startup zero-wipe); after first snapshot **always** writes zero (stale-badge clear); value-dedupe removed (SW may race a different value).
- `clearPwaAppBadgeOnLogout`: SW-first.
- `ChatDetailScreen`: open-chat badge total excludes its own conversation.

## Key files

- `frontend/web/web-push-sw.js` (rewritten)
- `frontend/lib/services/push_sw_channel_stub.dart` / `push_sw_channel_web.dart` (new)
- `frontend/lib/utils/pending_deep_link_stub.dart` / `pending_deep_link_web.dart` (new)
- `frontend/lib/services/notification_cleaner_web.dart` (rewritten), `unread_badge_sync.dart` (rewritten), `pwa_app_badge_clear.dart`, `web_push_bridge_web.dart`, `push_service.dart`
- `frontend/lib/providers/conversations_provider.dart` (`hasLoadedConversationsOnce`), `frontend/lib/main.dart`, `frontend/lib/screens/main_shell.dart`, `chat_detail_screen.dart`
- `frontend/test/services/unread_badge_sync_test.dart` (new, 5 tests)

## Verification

- `cd frontend && flutter analyze` → **No issues found** (the pre-existing `_buildApp` leading-underscore info in `main_shell_notification_nav_test.dart` was renamed in follow-up commit `e503ecf`).
- `cd frontend && flutter test` → **358 passed** (353 → +5 new badge tests; prior `main_shell_notification_nav_test.dart` still green — Bug 3 A→B switch preserved).
- Backend untouched → suite unaffected (290 unit tests count unchanged).
- **Manual on-device QA REQUIRED** (SW/JS-interop invisible to `flutter test`): matrix in the session conversation — 1/2/5/11 messages → one card with correct per-conv count; tap clears group + opens chat screen from cold/background/foreground; badge cumulative, clears on read, no reset-to-1 after silence; Android/desktop-web unaffected.

## Notes for next session

- **Deploy:** version bumped to **0.0.49**; remember stale-build trap (`flutter clean`, verify `gitCommit`, PWA cache-bust). iOS picks up the new SW on next PWA launch (byte-diff check) — may need one app restart after deploy before retesting.
- Known residual (true iOS limits, documented in CLAUDE.md §9): close-then-show relies on `getNotifications()`/`close()` which WebKit reports occasionally racy under rapid bursts; background badge is eventual-consistent (delayed APNs delivery from an older burst can flash a lower total).
- If `getUnreadSummaryForUser` ever fails at flush the SW now leaves the badge untouched (was: reset to 1). Backend logs `Push coalesce: unread summary failed` — worth watching after deploy.
