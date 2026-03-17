import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/models/conversation_model.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/models/message_model.dart';

void main() {
  group('ConversationsProvider', () {
    ConversationsProvider buildProviderWithSampleData() {
      final provider = ConversationsProvider();
      final userA = UserModel(id: 1, username: 'alice', tag: '0001');
      final userB = UserModel(id: 2, username: 'bob', tag: '0002');
      final conv1 = ConversationModel(
        id: 10,
        userOne: userA,
        userTwo: userB,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final conv2 = ConversationModel(
        id: 11,
        userOne: userB,
        userTwo: userA,
        createdAt: DateTime.utc(2026, 1, 2),
      );

      provider.onConnect(false);
      provider
        ..openConversation(conv1.id)
        ..updateLastMessage(
          conv1.id,
          MessageModel(
            id: 100,
            content: 'Hello',
            senderId: userA.id,
            senderUsername: userA.username,
            conversationId: conv1.id,
            createdAt: DateTime.utc(2026, 1, 1, 12),
          ),
        )
        ..updateUnreadCount(conv1.id, 1);

      // Inject conversations directly into internal list for testing
      provider
        ..clearAll()
        ..onConversationsList([
          {
            'id': conv1.id,
            'userOne': {
              'id': userA.id,
              'username': userA.username,
              'tag': userA.tag,
            },
            'userTwo': {
              'id': userB.id,
              'username': userB.username,
              'tag': userB.tag,
            },
            'createdAt': conv1.createdAt.toIso8601String(),
            'unreadCount': 1,
          },
          {
            'id': conv2.id,
            'userOne': {
              'id': userB.id,
              'username': userB.username,
              'tag': userB.tag,
            },
            'userTwo': {
              'id': userA.id,
              'username': userA.username,
              'tag': userA.tag,
            },
            'createdAt': conv2.createdAt.toIso8601String(),
            'unreadCount': 0,
          },
        ]);

      return provider;
    }

    test('onConnect(false) clears all state', () {
      final provider = buildProviderWithSampleData();

      provider.onConnect(false);

      expect(provider.conversations, isEmpty);
      expect(provider.activeConversationId, isNull);
      expect(provider.lastMessages, isEmpty);
      expect(provider.unreadCounts, isEmpty);
      expect(provider.pendingOpenConversationId, isNull);
      expect(provider.activeConversationDeletedByOther, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('onConnect(true) preserves conversations and active chat (no flicker)', () {
      final provider = buildProviderWithSampleData();
      provider.openConversation(10);

      provider.onConnect(true);

      expect(provider.conversations, isNotEmpty);
      expect(provider.activeConversationId, 10);
      expect(provider.activeConversationDeletedByOther, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('removeConversationsForUser removes conversations and clears active if needed', () {
      final provider = ConversationsProvider();
      final userA = UserModel(id: 1, username: 'alice', tag: '0001');
      final userB = UserModel(id: 2, username: 'bob', tag: '0002');

      final conv1 = ConversationModel(
        id: 10,
        userOne: userA,
        userTwo: userB,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final conv2 = ConversationModel(
        id: 11,
        userOne: userA,
        userTwo: userA,
        createdAt: DateTime.utc(2026, 1, 2),
      );

      provider.onConversationsList([
        {
          'id': conv1.id,
          'userOne': {
            'id': userA.id,
            'username': userA.username,
            'tag': userA.tag,
          },
          'userTwo': {
            'id': userB.id,
            'username': userB.username,
            'tag': userB.tag,
          },
          'createdAt': conv1.createdAt.toIso8601String(),
          'unreadCount': 0,
        },
        {
          'id': conv2.id,
          'userOne': {
            'id': userA.id,
            'username': userA.username,
            'tag': userA.tag,
          },
          'userTwo': {
            'id': userA.id,
            'username': userA.username,
            'tag': userA.tag,
          },
          'createdAt': conv2.createdAt.toIso8601String(),
          'unreadCount': 0,
        },
      ]);

      provider.openConversation(conv1.id);
      provider.removeConversationsForUser(userB.id);

      expect(provider.conversations.length, 1);
      expect(provider.conversations.first.id, conv2.id);
      expect(provider.activeConversationId, isNull);
    });
  });
}

