# Task 6 — NotificationCleaner conditional-import triple

**Date:** 2026-06-10

## What was done

Created the three `NotificationCleaner` service files (stub/io/web) plus a unit test, as Task 6 of the push-notification sweep feature.

- **Stub** (`notification_cleaner_stub.dart`): no-op `closeNotificationForConversation` and `sweepNotificationsKeepUnread` for platforms without local-notification support.
- **Android/io** (`notification_cleaner_io.dart`): uses `flutter_local_notifications` v21. `closeNotificationForConversation` calls `_plugin.cancel(id:, tag:)`. `sweepNotificationsKeepUnread` resolves `AndroidFlutterLocalNotificationsPlugin`, calls `getActiveNotifications()`, iterates tags with `conversation-` prefix, cancels those whose id is not in `unreadConversationIds`.
- **Web** (`notification_cleaner_web.dart`): uses `package:web` + `dart:js_interop`. Defines `@JS() extension type _ServiceWorkerRegistrationExt` to expose `getNotifications([filter])` (not in `package:web`'s typed API). Closes matched `Notification` objects via `callMethod('close')`. Posts `set-badge`/`clear-badge` to SW controller via `postMessage`.
- **Unit test** (`test/notification_cleaner_web_test.dart`): pure Dart sweep-decision logic (4 cases — partial unread, all unread, none unread, non-conversation tags). No JS interop needed.

One fix from spec: `FlutterLocalNotificationsPlugin.cancel()` in v21 uses named params `cancel({required int id, String? tag})` not positional.

## Key files
- `frontend/lib/services/notification_cleaner_stub.dart`
- `frontend/lib/services/notification_cleaner_io.dart`
- `frontend/lib/services/notification_cleaner_web.dart`
- `frontend/test/notification_cleaner_web_test.dart`

## Verification
- `flutter test test/notification_cleaner_web_test.dart` → 4/4 passed
- `flutter analyze lib/services/notification_cleaner_stub.dart lib/services/notification_cleaner_web.dart lib/services/notification_cleaner_io.dart` → No issues found

## Notes for next session
- These files are not yet wired up — the conditional import entrypoint and callsites in push notification handling are part of subsequent tasks.
- The `@JS() extension type` pattern (same as `web_push_bridge_web.dart`) was the correct approach for `getNotifications`; `package:web`'s `ServiceWorkerRegistration` does not expose it directly.
