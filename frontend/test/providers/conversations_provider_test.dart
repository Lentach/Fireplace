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
      expect(provider.pendingNotificationConversationId, isNull);
      expect(provider.activeConversationDeletedByOther, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test(
        'requestNavigateToConversationFromNotification pending is consumed and cleared',
        () {
      final provider = ConversationsProvider();
      provider.requestNavigateToConversationFromNotification(42);
      expect(provider.pendingNotificationConversationId, 42);
      expect(provider.consumePendingNotificationConversationId(), 42);
      expect(provider.pendingNotificationConversationId, isNull);
      expect(provider.consumePendingNotificationConversationId(), isNull);
    });

    test(
        'requestNavigateToConversationFromNotification ignores duplicate same id',
        () {
      final provider = ConversationsProvider();
      var notifies = 0;
      provider.addListener(() => notifies++);
      provider.requestNavigateToConversationFromNotification(7);
      expect(notifies, 1);
      provider.requestNavigateToConversationFromNotification(7);
      expect(notifies, 1);
      expect(provider.pendingNotificationConversationId, 7);
    });

    test('onConnect(false) clears pending notification conversation id', () {
      final provider = ConversationsProvider();
      provider.requestNavigateToConversationFromNotification(99);
      provider.onConnect(false);
      expect(provider.pendingNotificationConversationId, isNull);
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

    test('deleteConversation removes conversation optimistically and emits', () {
      final provider = buildProviderWithSampleData();
      final emitted = <Map<String, dynamic>>[];
      provider.setEmitCallback((event, data) {
        if (event == 'deleteConversationOnly') {
          emitted.add(Map<String, dynamic>.from(data as Map));
        }
      });

      provider.deleteConversation(10);

      expect(provider.conversations.length, 1);
      expect(provider.conversations.first.id, 11);
      expect(provider.lastMessages.containsKey(10), isFalse);
      expect(emitted.length, 1);
      expect(emitted.first['conversationId'], 10);
    });

    test(
        'onConversationsList keeps higher local unread when ahead of stale snapshot',
        () {
      final provider = ConversationsProvider();
      final userA = UserModel(id: 1, username: 'alice', tag: '0001');
      final userB = UserModel(id: 2, username: 'bob', tag: '0002');

      provider.onConnect(false);
      provider.onConversationsList([
        {
          'id': 10,
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
          'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
          'unreadCount': 0,
        },
      ]);

      provider.incrementUnreadCount(10);
      provider.incrementUnreadCount(10);
      expect(provider.getUnreadCount(10), 2);

      provider.onConversationsList([
        {
          'id': 10,
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
          'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
          'unreadCount': 1,
        },
      ]);

      expect(provider.getUnreadCount(10), 2);
    });

    test('onConversationsList forces zero unread for active conversation', () {
      final provider = ConversationsProvider();
      final userA = UserModel(id: 1, username: 'alice', tag: '0001');
      final userB = UserModel(id: 2, username: 'bob', tag: '0002');

      provider.onConnect(false);
      provider.setActiveConversation(10);

      provider.onConversationsList([
        {
          'id': 10,
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
          'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
          'unreadCount': 3,
        },
      ]);

      expect(provider.getUnreadCount(10), 0);
    });

    group('pushClientState (server push suppression)', () {
      test('setClientVisible false emits pushClientState with clientVisible false', () {
        final provider = ConversationsProvider();
        final pushStates = <Map<String, dynamic>>[];
        provider.setEmitCallback((event, data) {
          if (event == 'pushClientState') {
            pushStates.add(Map<String, dynamic>.from(data as Map));
          }
        });
        provider.onConnect(false);
        provider.openConversation(42);
        pushStates.clear();

        provider.setClientVisible(false);

        expect(pushStates, hasLength(1));
        expect(pushStates.single['clientVisible'], isFalse);
        expect(pushStates.single['activeConversationId'], 42);
      });

      test('setClientVisible false is idempotent (no duplicate emits)', () {
        final provider = ConversationsProvider();
        provider.onConnect(false);
        provider.openConversation(1);
        var pushAfterSetup = 0;
        provider.setEmitCallback((event, _) {
          if (event == 'pushClientState') pushAfterSetup++;
        });

        provider.setClientVisible(false);
        expect(pushAfterSetup, 1);
        provider.setClientVisible(false);
        expect(pushAfterSetup, 1);
      });

      test('closeConversation emits activeConversationId null for pushClientState', () {
        final provider = ConversationsProvider();
        final pushStates = <Map<String, dynamic>>[];
        provider.setEmitCallback((event, data) {
          if (event == 'pushClientState') {
            pushStates.add(Map<String, dynamic>.from(data as Map));
          }
        });
        provider.onConnect(false);
        provider.openConversation(99);
        pushStates.clear();

        provider.closeConversation();

        expect(pushStates, hasLength(1));
        expect(pushStates.single['activeConversationId'], isNull);
        expect(pushStates.single['clientVisible'], isTrue);
      });
    });
  });
}

