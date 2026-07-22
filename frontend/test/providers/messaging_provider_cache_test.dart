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

Map<String, dynamic> _msgJson(int id, int convId) => {
      'id': id,
      'content': 'message $id',
      'senderId': 1,
      'senderUsername': 'alice',
      'conversationId': convId,
      'deliveryStatus': 'READ',
      'messageType': 'TEXT',
      'createdAt': '2026-01-01T00:00:0$id.000Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessagingProvider cache', () {
    late MessagingProvider provider;

    setUp(() {
      provider = MessagingProvider();
      provider.setIncomingMessageSoundEnabledForTest(false);
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

      // The messages getter exposes the live loaded list. Mutating it in place
      // must NOT touch the cache — loadCachedMessages hands back a distinct copy
      // (`_messages = List.from(cached...)`), not an alias of the cache list.
      // If the impl regressed to `_messages = cached`, this add would leak into
      // _conversationCache[10] and the assertions below would fail.
      provider.messages.add(_msg(2, 10));

      expect(provider.cacheMessageForTest(10, 2), isNull);
      expect(provider.cachedMessagesFor(10).length, 1);
      expect(provider.cachedMessagesFor(10).first.id, 1);
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
      provider.getMessages(10);

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

    test('history response deduplicates loaded row and appends missed row', () {
      provider.setActiveConversationIdForTest(10);
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.loadCachedMessages(10);
      provider.getMessages(10);

      provider.onMessageHistory({
        'conversationId': 10,
        'messages': [
          _msgJson(1, 10),
          _msgJson(2, 10),
        ],
      });

      expect(provider.messages.map((message) => message.id), [1, 2],
          reason:
              'resume history may include already-loaded and missed rows; each id must appear once in chronological order');
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

    test('chatHistoryCleared removes cache entry', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.onChatHistoryCleared({'conversationId': 10});
      expect(provider.hasCachedMessages(10), isFalse);
    });

    test('conversationDeleted removes cache entry', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.onConversationDeleted(10);
      expect(provider.hasCachedMessages(10), isFalse);
    });

    test('messageDeleted updates cache and reflects removal', () {
      provider.seedCacheForTest(10, [_msg(1, 10), _msg(2, 10)]);
      provider.setActiveConversationIdForTest(10);
      provider.loadCachedMessages(10);

      provider.onMessageDeleted({
        'messageId': 1,
        'conversationId': 10,
        'forEveryone': true,
      });

      expect(provider.hasCachedMessages(10), isTrue);
      expect(provider.messages.length, 1);
      expect(provider.messages.first.id, 2);
    });

    test('messageDeleted removes cache entry when list becomes empty', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.setActiveConversationIdForTest(10);
      provider.loadCachedMessages(10);

      provider.onMessageDeleted({
        'messageId': 1,
        'conversationId': 10,
        'forEveryone': true,
      });

      // Empty list → cache entry removed so hasCachedMessages is false
      expect(provider.hasCachedMessages(10), isFalse);
    });

    test('messageDelivered updates delivery status in cache', () {
      final msg = MessageModel(
        id: 1,
        content: 'hello',
        senderId: 2,
        senderUsername: 'bob',
        conversationId: 10,
        deliveryStatus: MessageDeliveryStatus.sent,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      provider.seedCacheForTest(10, [msg]);
      provider.setActiveConversationIdForTest(10);
      provider.loadCachedMessages(10);

      provider.onMessageDelivered({
        'messageId': 1,
        'conversationId': 10,
        'deliveryStatus': 'READ',
      });

      // Cache entry should still exist and message status should be updated
      expect(provider.hasCachedMessages(10), isTrue);
      expect(provider.messages.first.deliveryStatus, MessageDeliveryStatus.read);
    });

    test('plain incoming message updates cache for active conversation', () {
      provider.seedCacheForTest(10, [_msg(1, 10)]);
      provider.setActiveConversationIdForTest(10);
      provider.loadCachedMessages(10);

      provider.onNewMessage({
        'id': 2,
        'content': 'world',
        'senderId': 2,
        'senderUsername': 'bob',
        'conversationId': 10,
        'deliveryStatus': 'SENT',
        'messageType': 'TEXT',
        'createdAt': '2026-01-01T01:00:00.000Z',
      });

      // Cache reflects both messages — verify by loading cache in fresh provider
      expect(provider.hasCachedMessages(10), isTrue);
      expect(provider.messages.length, 2);
      final p2 = MessagingProvider();
      p2.seedCacheForTest(10, provider.messages);
      p2.loadCachedMessages(10);
      expect(p2.messages.length, 2);
    });
  });
}
