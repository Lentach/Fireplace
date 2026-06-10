import 'package:flutter_test/flutter_test.dart';

/// Pure decision logic extracted for testing — given active notification tags
/// and the set of still-unread conversation IDs, which tag IDs should be closed?
Set<int> idsToClose({
  required List<String> activeTags,
  required Set<int> unreadConversationIds,
}) {
  const prefix = 'conversation-';
  final result = <int>{};
  for (final tag in activeTags) {
    if (!tag.startsWith(prefix)) continue;
    final id = int.tryParse(tag.substring(prefix.length));
    if (id != null && !unreadConversationIds.contains(id)) {
      result.add(id);
    }
  }
  return result;
}

void main() {
  group('sweepNotificationsKeepUnread decision logic', () {
    test('closes notifications not in unread set', () {
      final toClose = idsToClose(
        activeTags: ['conversation-42', 'conversation-17', 'conversation-9', 'new-message'],
        unreadConversationIds: {17},
      );
      expect(toClose, containsAll([42, 9]));
      expect(toClose, isNot(contains(17)));
    });

    test('keeps all when all are unread', () {
      final toClose = idsToClose(
        activeTags: ['conversation-1', 'conversation-2'],
        unreadConversationIds: {1, 2},
      );
      expect(toClose, isEmpty);
    });

    test('closes all when unread set is empty', () {
      final toClose = idsToClose(
        activeTags: ['conversation-10', 'conversation-20'],
        unreadConversationIds: {},
      );
      expect(toClose, containsAll([10, 20]));
    });

    test('ignores non-conversation tags', () {
      final toClose = idsToClose(
        activeTags: ['new-message', 'some-other-tag'],
        unreadConversationIds: {},
      );
      expect(toClose, isEmpty);
    });
  });
}
