/// Maximum integer shown on the app icon badge (saturation cap).
///
/// **Keep in sync** with `APP_BADGE_MAX` in `frontend/web/web-push-sw.js`.
const int kAppBadgeMaxDisplayCount = 19;

/// Sum of per-conversation unread counts (same semantics as [ConversationsProvider.unreadCounts]).
int sumUnreadBadgeCounts(Map<int, int> unreadByConversationId) {
  var sum = 0;
  for (final n in unreadByConversationId.values) {
    sum += n;
  }
  return sum;
}

/// Caps total unread for the OS app badge at [kAppBadgeMaxDisplayCount]. Returns **0** when [totalUnread] <= 0.
///
/// **WebKit (Safari / iOS PWA)** often does not display a badge when [Navigator.setAppBadge]
/// is called with **no arguments**; passing a **positive integer** restores the icon badge there.
int capUnreadForBadge(int totalUnread) {
  if (totalUnread <= 0) return 0;
  return totalUnread > kAppBadgeMaxDisplayCount
      ? kAppBadgeMaxDisplayCount
      : totalUnread;
}
