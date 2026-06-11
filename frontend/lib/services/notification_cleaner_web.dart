import '../utils/app_badge_math.dart';
import 'badging_bridge_web.dart';
import 'push_sw_channel_web.dart';

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
