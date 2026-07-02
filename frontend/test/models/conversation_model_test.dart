import 'package:flutter_test/flutter_test.dart';
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
  });
}
