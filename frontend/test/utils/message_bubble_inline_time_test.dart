import 'package:fireplace/config/app_config.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/widgets/message/message_bubble_inline_time.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _msg(String content) => MessageModel(
  id: 1,
  content: content,
  senderId: 1,
  senderUsername: 'alice',
  conversationId: 1,
  createdAt: DateTime(2026, 5, 23),
  deliveryStatus: MessageDeliveryStatus.sent,
  messageType: MessageType.text,
);

void main() {
  group('messageBubbleUsesInlineTime', () {
    test('true for single-line plain text', () {
      final message = _msg('hi there');
      expect(
        messageBubbleUsesInlineTime(
          message: message,
          displayContent: 'hi there',
        ),
        isTrue,
      );
    });

    test('false for a note-URL displayContent', () {
      // The gate calls isAntiQuantumNoteUrl WITHOUT an explicit baseUrl, so the
      // URL must be built from AppConfig.baseUrl to trigger detection.
      const hex = '0123456789abcdef0123456789abcdef';
      final noteUrl = '${AppConfig.baseUrl}/note/$hex#abcABC012_-';
      final message = _msg(noteUrl);
      expect(
        messageBubbleUsesInlineTime(
          message: message,
          displayContent: noteUrl,
        ),
        isFalse,
      );
    });
  });
}
