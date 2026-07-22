import 'package:fireplace/config/app_config.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/widgets/message/message_bubble_inline_time.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _msg(
  String content, {
  MessageType messageType = MessageType.text,
  String? linkPreviewUrl,
  ReplyToPreview? replyTo,
}) => MessageModel(
  id: 1,
  content: content,
  senderId: 1,
  senderUsername: 'alice',
  conversationId: 1,
  createdAt: DateTime(2026, 5, 23),
  deliveryStatus: MessageDeliveryStatus.sent,
  messageType: messageType,
  linkPreviewUrl: linkPreviewUrl,
  replyTo: replyTo,
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

    test('false for multiline text', () {
      final message = _msg('line1\nline2');
      expect(
        messageBubbleUsesInlineTime(
          message: message,
          displayContent: 'line1\nline2',
        ),
        isFalse,
      );
    });

    test('true for ping', () {
      final message = _msg('ping', messageType: MessageType.ping);
      expect(
        messageBubbleUsesInlineTime(message: message, displayContent: 'ping'),
        isTrue,
      );
    });

    test('false for image and file', () {
      for (final type in [MessageType.image, MessageType.file]) {
        final message = _msg('media', messageType: type);
        expect(
          messageBubbleUsesInlineTime(
            message: message,
            displayContent: 'media',
          ),
          isFalse,
        );
      }
    });

    test('false when a link preview is attached', () {
      final message = _msg('see this', linkPreviewUrl: 'https://example.com');
      expect(
        messageBubbleUsesInlineTime(
          message: message,
          displayContent: 'see this',
        ),
        isFalse,
      );
    });

    test('false when the message is a reply', () {
      final message = _msg(
        'reply body',
        replyTo: const ReplyToPreview(
          id: 9,
          content: 'original',
          senderUsername: 'bob',
          messageType: MessageType.text,
        ),
      );
      expect(
        messageBubbleUsesInlineTime(
          message: message,
          displayContent: 'reply body',
        ),
        isFalse,
      );
    });
  });
}
