import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessagingProvider composer focus on reply', () {
    test('setReplyingTo invokes registered composer focus request', () {
      final provider = MessagingProvider();
      var focusCalls = 0;
      provider.setComposerFocusRequest(() => focusCalls++);

      provider.setReplyingTo(
        MessageModel(
          id: 1,
          content: 'hello',
          senderId: 2,
          senderUsername: 'bob',
          conversationId: 10,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(focusCalls, 1);
      expect(provider.replyingToMessage?.id, 1);

      provider.setReplyingTo(null);
      expect(focusCalls, 1);
    });
  });
}
