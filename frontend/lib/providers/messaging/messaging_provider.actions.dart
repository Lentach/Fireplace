part of '../messaging_provider.dart';

// These extension methods live in MessagingProvider's own library and operate on
// its private state, so calling the ChangeNotifier's `notifyListeners()` here is
// legitimate; the analyzer's protected / visible-for-testing checks (which assume
// the call sits in a ChangeNotifier subclass body, not an extension) don't apply.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// User- and timer-driven mutations: read / clear / delete / pin / react / expiry.
extension MessagingActions on MessagingProvider {
  void markConversationRead(int conversationId) {
    _emit?.call('markConversationRead', {'conversationId': conversationId});
  }

  void clearChatHistory(int conversationId) {
    _emit?.call('clearChatHistory', {'conversationId': conversationId});
  }

  void deleteMessage(int messageId, {required bool forEveryone}) {
    _emit?.call('deleteMessage', {
      'messageId': messageId,
      'mode': forEveryone ? 'for_everyone' : 'for_me',
    });
  }

  void pinMessage(int conversationId, int messageId) {
    final local = messageById(messageId);
    if (local != null) {
      _conversationsProvider?.setPinnedPreviewOptimistic(
        conversationId,
        messageId,
        local,
      );
    }
    _emit?.call('pinMessage', {
      'conversationId': conversationId,
      'messageId': messageId,
    });
  }

  void unpinMessage(int conversationId) {
    _emit?.call('unpinMessage', {'conversationId': conversationId});
  }

  void addReaction(int messageId, String emoji) {
    _emit?.call('addReaction', {'messageId': messageId, 'emoji': emoji});
  }

  void removeReaction(int messageId, String emoji) {
    _emit?.call('removeReaction', {'messageId': messageId, 'emoji': emoji});
  }

  /// Remove messages whose expiresAt has passed. Called every second by ChatDetailScreen timer.
  void removeExpiredMessages() {
    final now = DateTime.now();
    final hadExpiredInList = _messages.any((m) => isMessageExpired(m, now));
    var hadExpiredInCache = false;
    for (final cid in _conversationCache.keys.toList()) {
      final list = _conversationCache[cid];
      if (list == null) continue;
      final before = list.length;
      list.removeWhere((m) => isMessageExpired(m, now));
      if (list.length != before) hadExpiredInCache = true;
      if (list.isEmpty) _conversationCache.remove(cid);
    }
    if (!hadExpiredInList && !hadExpiredInCache) return;

    _messages.removeWhere((m) => isMessageExpired(m, now));
    _conversationsProvider?.pruneExpiredLastMessages();
    notifyListeners();
  }
}
