/// Stub — no-op on platforms without local notification support (iOS native not in scope).
class NotificationCleaner {
  Future<void> closeNotificationForConversation(
    int conversationId, {
    required int newUnreadTotal,
  }) async {}

  Future<void> sweepNotificationsKeepUnread(
    Set<int> unreadConversationIds,
    int unreadTotal,
  ) async {}
}

NotificationCleaner createNotificationCleaner() => NotificationCleaner();
