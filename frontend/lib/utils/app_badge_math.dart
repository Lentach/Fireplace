/// Sum of per-conversation unread counts (same semantics as [ConversationsProvider.unreadCounts]).
///
/// Used by [UnreadBadgeSync] to decide whether to show a generic PWA app icon badge (dot).
int sumUnreadBadgeCounts(Map<int, int> unreadByConversationId) {
  var sum = 0;
  for (final n in unreadByConversationId.values) {
    sum += n;
  }
  return sum;
}
