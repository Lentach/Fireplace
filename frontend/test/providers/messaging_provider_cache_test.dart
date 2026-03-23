import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/models/message_model.dart';

MessageModel _msg(int id, int convId) => MessageModel(
      id: id,
      content: 'hello',
      senderId: 1,
      senderUsername: 'alice',
      conversationId: convId,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('MessagingProvider cache', () {
    late MessagingProvider provider;

    setUp(() {
      provider = MessagingProvider();
      // onConnect signature is: void onConnect(bool isReconnect)
      // userId and token are set separately via dedicated setters.
      provider.onConnect(false);
      provider.setCurrentUserId(1);
      provider.setToken('tok');
    });

    test('hasCachedMessages returns false when no cache', () {
      expect(provider.hasCachedMessages(42), isFalse);
    });

    test('loadCachedMessages returns false when no cache', () {
      final result = provider.loadCachedMessages(42);
      expect(result, isFalse);
      expect(provider.messages, isEmpty);
    });

    test('loadCachedMessages returns true and sets messages when cache exists', () {
      provider.seedCacheForTest(10, [_msg(1, 10), _msg(2, 10)]);

      final result = provider.loadCachedMessages(10);
      expect(result, isTrue);
      expect(provider.messages.length, 2);
      expect(provider.messages.first.id, 1);
    });

    test('loadCachedMessages returns a copy — provider messages are independent of cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.loadCachedMessages(10);
      // Cache must still be intact after loading (List.from copy)
      expect(provider.hasCachedMessages(10), isTrue);
    });

    test('clearAll clears the cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.clearAll();
      expect(provider.hasCachedMessages(10), isFalse);
    });

    test('clearMessages does NOT clear the cache', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.clearMessages();
      // Cache survives back-navigation (clearMessages is called on back button)
      expect(provider.hasCachedMessages(10), isTrue);
    });

    test('onConnect does NOT clear the cache', () {
      // Cache is session-scoped — a fresh socket connect (same session, same user)
      // must NOT evict cache entries.
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.onConnect(false);
      expect(provider.hasCachedMessages(10), isTrue);
    });

    test('onMessageHistory populates cache for active conversation', () {
      provider.setActiveConversationIdForTest(10);

      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [
          {
            'id': 1,
            'content': 'hello',
            'senderId': 1,
            'senderUsername': 'alice',
            'conversationId': 10,
            'deliveryStatus': 'READ',
            'messageType': 'TEXT',
            'createdAt': '2026-01-01T00:00:00.000Z',
          }
        ],
      });

      // Cache populated synchronously (with encrypted placeholders; decrypted version follows async)
      expect(provider.hasCachedMessages(10), isTrue);
      expect(provider.messages.length, 1);
    });

    test('onMessageHistory for a different conversation is ignored', () {
      provider.setActiveConversationIdForTest(10);

      provider.onMessageHistory({
        'conversationId': 99,
        'messages': [],
      });

      expect(provider.hasCachedMessages(99), isFalse);
      expect(provider.hasCachedMessages(10), isFalse);
    });
  });
}
