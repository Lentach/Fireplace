import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/models/conversation_model.dart';

void main() {
  group('ConversationModel', () {
    test('fromJson parses conversation', () {
      final json = {
        'id': 1,
        'userOne': {'id': 10, 'username': 'alice'},
        'userTwo': {'id': 20, 'username': 'bob'},
        'createdAt': '2026-02-01T12:00:00.000Z',
      };
      final conv = ConversationModel.fromJson(json);
      expect(conv.id, 1);
      expect(conv.userOne.id, 10);
      expect(conv.userOne.username, 'alice');
      expect(conv.userTwo.id, 20);
      expect(conv.userTwo.username, 'bob');
      expect(conv.createdAt, DateTime.utc(2026, 2, 1, 12, 0, 0));
    });

    test('fromJson maps pinnedMessage JSON key to pinnedMessagePreview', () {
      final json = {
        'id': 2,
        'userOne': {'id': 10, 'username': 'alice'},
        'userTwo': {'id': 20, 'username': 'bob'},
        'createdAt': '2026-02-01T12:00:00.000Z',
        'disappearingTimer': 3600,
        'pinnedMessageId': 77,
        'pinnedMessage': {
          'id': 77,
          'content': '[encrypted]',
          'senderId': 10,
          'senderUsername': 'alice',
          'conversationId': 2,
          'deliveryStatus': 'READ',
          'messageType': 'TEXT',
          'createdAt': '2026-02-01T13:00:00.000Z',
        },
      };
      final conv = ConversationModel.fromJson(json);
      expect(conv.disappearingTimer, 3600);
      expect(conv.pinnedMessageId, 77);
      // The wire key is 'pinnedMessage'; the field is pinnedMessagePreview.
      // A mapper regression reading 'pinnedMessagePreview' would break the
      // pinned-banner feature while still passing the base parse test.
      expect(conv.pinnedMessagePreview, isNotNull);
      expect(conv.pinnedMessagePreview!.id, 77);
      expect(conv.pinnedMessagePreview!.senderUsername, 'alice');
    });

    test('fromJson leaves pinned/timer fields null when absent', () {
      final json = {
        'id': 3,
        'userOne': {'id': 10, 'username': 'alice'},
        'userTwo': {'id': 20, 'username': 'bob'},
        'createdAt': '2026-02-01T12:00:00.000Z',
      };
      final conv = ConversationModel.fromJson(json);
      expect(conv.disappearingTimer, isNull);
      expect(conv.pinnedMessageId, isNull);
      expect(conv.pinnedMessagePreview, isNull);
    });

    test('isMutedAt ignores an expired mute while retaining forever mute', () {
      final conversation = ConversationModel(
        id: 4,
        userOne: UserModel(id: 10, username: 'alice', tag: '0001'),
        userTwo: UserModel(id: 20, username: 'bob', tag: '0002'),
        createdAt: DateTime.utc(2026, 2, 1),
        muted: true,
        mutedUntil: DateTime.utc(2026, 7, 13, 11, 59, 59),
      );
      final foreverMuted = ConversationModel(
        id: 5,
        userOne: UserModel(id: 10, username: 'alice', tag: '0001'),
        userTwo: UserModel(id: 20, username: 'bob', tag: '0002'),
        createdAt: DateTime.utc(2026, 2, 1),
        muted: true,
      );
      final now = DateTime.utc(2026, 7, 13, 12);

      expect(conversation.isMutedAt(now), isFalse);
      expect(foreverMuted.isMutedAt(now), isTrue);
    });

    test('isMutedAt honors an active timed mute and ignores mute flag off', () {
      final now = DateTime.utc(2026, 7, 13, 12);
      final activeMute = ConversationModel(
        id: 6,
        userOne: UserModel(id: 10, username: 'alice', tag: '0001'),
        userTwo: UserModel(id: 20, username: 'bob', tag: '0002'),
        createdAt: DateTime.utc(2026, 2, 1),
        muted: true,
        mutedUntil: DateTime.utc(2026, 7, 13, 12, 0, 1),
      );
      final unmutedWithFutureUntil = ConversationModel(
        id: 7,
        userOne: UserModel(id: 10, username: 'alice', tag: '0001'),
        userTwo: UserModel(id: 20, username: 'bob', tag: '0002'),
        createdAt: DateTime.utc(2026, 2, 1),
        muted: false,
        mutedUntil: DateTime.utc(2026, 7, 13, 12, 0, 1),
      );

      // Active timed mute: mutedUntil after now -> still muted.
      expect(activeMute.isMutedAt(now), isTrue);
      // muted flag off -> never muted, regardless of mutedUntil.
      expect(unmutedWithFutureUntil.isMutedAt(now), isFalse);
    });

    test('copyWith clears disappearingTimer to null via clearDisappearingTimer',
        () {
      final base = ConversationModel(
        id: 6,
        userOne: UserModel(id: 10, username: 'alice', tag: '0001'),
        userTwo: UserModel(id: 20, username: 'bob', tag: '0002'),
        createdAt: DateTime.utc(2026, 2, 1),
        disappearingTimer: 3600,
      );

      // Not touched -> preserved.
      expect(base.copyWith(muted: true).disappearingTimer, 3600);
      // Set to a new value.
      expect(base.copyWith(disappearingTimer: 60).disappearingTimer, 60);
      // Turn OFF: without the clear flag the null-merge idiom would keep 3600
      // (the disappearing-timer-OFF-not-honored-on-peer bug). The flag clears it.
      expect(
        base.copyWith(clearDisappearingTimer: true).disappearingTimer,
        isNull,
      );
    });
  });
}
