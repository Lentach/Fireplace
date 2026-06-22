import 'package:fireplace/models/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageModel.editedAt', () {
    test('fromJson parses editedAt ISO string', () {
      final msg = MessageModel.fromJson({
        'id': 1,
        'content': '[encrypted]',
        'senderId': 1,
        'conversationId': 1,
        'createdAt': '2026-06-22T10:00:00.000Z',
        'editedAt': '2026-06-22T10:05:00.000Z',
      });
      expect(msg.editedAt, DateTime.parse('2026-06-22T10:05:00.000Z'));
    });

    test('fromJson leaves editedAt null when absent', () {
      final msg = MessageModel.fromJson({
        'id': 1,
        'content': 'hi',
        'senderId': 1,
        'conversationId': 1,
        'createdAt': '2026-06-22T10:00:00.000Z',
      });
      expect(msg.editedAt, isNull);
    });

    test('copyWith sets editedAt and preserves it', () {
      final base = MessageModel(
        id: 1,
        content: 'hi',
        senderId: 1,
        senderUsername: 'alice',
        conversationId: 1,
        createdAt: DateTime(2026, 6, 22, 10),
      );
      expect(base.editedAt, isNull);
      final edited = base.copyWith(
        content: 'hello',
        editedAt: DateTime(2026, 6, 22, 10, 5),
      );
      expect(edited.editedAt, DateTime(2026, 6, 22, 10, 5));
      // Preserved when not passed.
      expect(edited.copyWith(content: 'again').editedAt,
          DateTime(2026, 6, 22, 10, 5));
    });
  });
}
