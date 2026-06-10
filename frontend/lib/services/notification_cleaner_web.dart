import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS()
extension type _ServiceWorkerRegistrationExt(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSObject>> getNotifications([JSObject? filter]);
}

/// Web — sweeps tray notifications via SW getNotifications + updates badge via SW postMessage.
class NotificationCleaner {
  Future<void> closeNotificationForConversation(
    int conversationId, {
    required int newUnreadTotal,
  }) async {
    try {
      final reg = await web.window.navigator.serviceWorker.ready.toDart;
      final regExt = _ServiceWorkerRegistrationExt(reg as JSObject);
      final opts = {'tag': 'conversation-$conversationId'}.jsify()! as JSObject;
      final notifications = await regExt.getNotifications(opts).toDart;
      final list = notifications.toDart;
      for (final n in list) {
        n.callMethod<JSAny?>('close'.toJS);
      }
    } catch (_) {}
    _postBadgeMessage(newUnreadTotal);
  }

  Future<void> sweepNotificationsKeepUnread(
    Set<int> unreadConversationIds,
    int unreadTotal,
  ) async {
    try {
      final reg = await web.window.navigator.serviceWorker.ready.toDart;
      final regExt = _ServiceWorkerRegistrationExt(reg as JSObject);
      final notifications = await regExt.getNotifications().toDart;
      final list = notifications.toDart;
      const prefix = 'conversation-';
      for (final n in list) {
        final tagJs = n.getProperty<JSString?>('tag'.toJS);
        final tag = tagJs?.toDart ?? '';
        if (!tag.startsWith(prefix)) continue;
        final id = int.tryParse(tag.substring(prefix.length));
        if (id != null && !unreadConversationIds.contains(id)) {
          n.callMethod<JSAny?>('close'.toJS);
        }
      }
    } catch (_) {}
    _postBadgeMessage(unreadTotal);
  }

  void _postBadgeMessage(int count) {
    try {
      final controller = web.window.navigator.serviceWorker.controller;
      if (controller == null) return;
      if (count <= 0) {
        controller.postMessage({'type': 'clear-badge'}.jsify());
      } else {
        controller.postMessage({'type': 'set-badge', 'count': count}.jsify());
      }
    } catch (_) {}
  }
}

NotificationCleaner createNotificationCleaner() => NotificationCleaner();
