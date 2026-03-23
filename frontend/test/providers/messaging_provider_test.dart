import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/providers/messaging_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _msgJson(int id, int convId) => {
      'id': id,
      'content': 'hello',
      'senderId': 1,
      'senderUsername': 'alice',
      'conversationId': convId,
      'deliveryStatus': 'READ',
      'messageType': 'TEXT',
      'createdAt': '2026-01-01T00:00:00.000Z',
    };

Map<String, dynamic> _history(int convId, List<Map<String, dynamic>> msgs) => {
      'conversationId': convId,
      'messages': msgs,
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MessagingProvider pagination', () {
    late MessagingProvider provider;

    setUp(() {
      provider = MessagingProvider();
      provider.onConnect(false);
      provider.setCurrentUserId(1);
      provider.setToken('tok');
    });

    test('loadOlderMessages prepends messages and updates hasMoreMessages', () {
      provider.setActiveConversationIdForTest(10);

      // Initial load: full page of 50 → _hasMore = true, _paginationOffset = 50.
      provider.getMessages(10);
      final initialMsgs = List.generate(50, (i) => _msgJson(i + 1, 10));
      provider.onMessageHistory(_history(10, initialMsgs));

      expect(provider.hasMoreMessages, isTrue);
      expect(provider.messages.length, 50);

      // Load older: only 3 messages come back (< pageSize) → _hasMore = false.
      provider.loadOlderMessages(10);
      final olderMsgs = List.generate(3, (i) => _msgJson(100 + i, 10));
      provider.onMessageHistory(_history(10, olderMsgs));

      // Older messages are prepended, loading flag cleared, no more pages.
      expect(provider.isLoadingMore, isFalse);
      expect(provider.hasMoreMessages, isFalse);
      expect(provider.messages.length, 53);
      expect(provider.messages.first.id, 100); // oldest at front
      expect(provider.messages.last.id, 50);   // newest at back
    });

    test('loadOlderMessages is no-op when hasMoreMessages is false', () {
      provider.setActiveConversationIdForTest(10);

      // Initial load with fewer than a full page → _hasMore = false.
      provider.getMessages(10);
      provider.onMessageHistory(_history(10, [_msgJson(1, 10), _msgJson(2, 10)]));

      expect(provider.hasMoreMessages, isFalse);

      // Call should return immediately without changing state.
      provider.loadOlderMessages(10);

      expect(provider.isLoadingMore, isFalse);
      expect(provider.messages.length, 2);
    });

    test('loadOlderMessages ignores stale response for wrong conversation', () {
      provider.setActiveConversationIdForTest(10);

      // Initial load: full page → _hasMore = true, _paginationConversationId = 10.
      provider.getMessages(10);
      final initialMsgs = List.generate(50, (i) => _msgJson(i + 1, 10));
      provider.onMessageHistory(_history(10, initialMsgs));

      // Trigger pagination load for conv 10.
      provider.loadOlderMessages(10);
      expect(provider.isLoadingMore, isTrue);

      // Stale response arrives with a different conversationId — must be ignored.
      final staleMsgs = List.generate(10, (i) => _msgJson(200 + i, 99));
      provider.onMessageHistory(_history(99, staleMsgs));

      // The 50 original messages must be unchanged.
      expect(provider.messages.length, 50);
      expect(provider.messages.every((m) => m.conversationId == 10), isTrue);
    });
  });
}
