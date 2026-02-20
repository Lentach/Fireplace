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
  });
}
