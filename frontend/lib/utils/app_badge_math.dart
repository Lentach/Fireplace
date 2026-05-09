/// Sum of per-conversation unread counts (same semantics as [ConversationsProvider.unreadCounts]).
int sumUnreadBadgeCounts(Map<int, int> unreadByConversationId) {
  var sum = 0;
  for (final n in unreadByConversationId.values) {
    sum += n;
  }
  return sum;
}

/// Caps total unread for the OS app badge (max **19**). Returns **0** when [totalUnread] <= 0
/// (caller should clear the badge, not call `setAppBadge(0)`).
int capUnreadForBadge(int totalUnread) {
  if (totalUnread <= 0) return 0;
  return totalUnread > 19 ? 19 : totalUnread;
}
