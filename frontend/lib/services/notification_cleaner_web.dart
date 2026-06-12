import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../utils/app_badge_math.dart';
import 'badging_bridge_web.dart';
import 'push_sw_channel_web.dart';

@JS()
extension type _RegistrationWithNotifications(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSObject>> getNotifications();
}

/// Web — asks the **push SW** (scope `/web-push-scope/`) to close tray
/// notifications and update the app badge via postMessage.
///
/// All tray + badge work runs inside the push SW ('close-conv' / 'sweep'
/// message handlers in web-push-sw.js): iOS WebKit requires SW context for
/// these to be reliable, and routing through one worker serializes them with
/// the push handler's own writes. The page-side Badging API is only a fallback
/// for when the push SW is not registered (push permission never granted).
class NotificationCleaner {
  final PushSwChannel _channel = PushSwChannel();
  final BadgingBridge _badgingBridge = BadgingBridge();

  Future<void> closeNotificationForConversation(
    int conversationId, {
    required int newUnreadTotal,
  }) async {
    final delivered = await _channel.postMessage({
      'type': 'close-conv',
      'conversationId': conversationId,
      'unreadTotal': newUnreadTotal,
    });
    // Best-effort page-context pass too: the SW-side sweep can only see
    // notifications shown by the CURRENT SW instance (iOS WebKit limitation);
    // the page's view of the registration is a separate query path, so try it
    // as well — harmless no-op where it returns nothing.
    await _closeFromPageContext(conversationId);
    if (!delivered) await _setBadgeFallback(newUnreadTotal);
  }

  Future<void> sweepNotificationsKeepUnread(
    Set<int> unreadConversationIds,
    int unreadTotal,
  ) async {
    final delivered = await _channel.postMessage({
      'type': 'sweep',
      'unreadConversationIds': unreadConversationIds.toList(),
      'unreadTotal': unreadTotal,
    });
    if (!delivered) await _setBadgeFallback(unreadTotal);
  }

  Future<void> _closeFromPageContext(int conversationId) async {
    try {
      final regAny = await web.window.navigator.serviceWorker
          .getRegistration(PushSwChannel.pushSwScope)
          .toDart;
      if (regAny.isUndefinedOrNull) return;
      final reg = _RegistrationWithNotifications(regAny as JSObject);
      final notifications = await reg.getNotifications().toDart;
      final tag = 'conversation-$conversationId';
      for (final n in notifications.toDart) {
        final tagJs = n.getProperty<JSString?>('tag'.toJS);
        if (tagJs?.toDart == tag) {
          n.callMethod<JSAny?>('close'.toJS);
        }
      }
    } catch (_) {}
  }

  Future<void> _setBadgeFallback(int unreadTotal) async {
    if (!_badgingBridge.isSupported) return;
    final capped = capUnreadForBadge(unreadTotal);
    if (capped == 0) {
      await _badgingBridge.clearBadge();
    } else {
      await _badgingBridge.setBadgeCount(capped);
    }
  }
}

NotificationCleaner createNotificationCleaner() => NotificationCleaner();
