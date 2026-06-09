import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android native — cancels local notifications via flutter_local_notifications.
class NotificationCleaner {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> closeNotificationForConversation(
    int conversationId, {
    required int newUnreadTotal,
  }) async {
    try {
      await _plugin.cancel(
        id: conversationId,
        tag: 'conversation-$conversationId',
      );
    } catch (_) {}
  }

  Future<void> sweepNotificationsKeepUnread(
    Set<int> unreadConversationIds,
    int unreadTotal,
  ) async {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) return;
      final active = await androidPlugin.getActiveNotifications();
      const prefix = 'conversation-';
      for (final n in active) {
        final tag = n.tag ?? '';
        if (!tag.startsWith(prefix)) continue;
        final id = int.tryParse(tag.substring(prefix.length));
        if (id != null && !unreadConversationIds.contains(id)) {
          await _plugin.cancel(id: n.id ?? id, tag: tag);
        }
      }
    } catch (_) {}
  }
}

NotificationCleaner createNotificationCleaner() => NotificationCleaner();
