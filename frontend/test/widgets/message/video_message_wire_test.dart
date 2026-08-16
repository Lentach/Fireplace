import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/utils/reply_preview_helper.dart';
import 'package:fireplace/widgets/message/message_content_factory.dart';
import 'package:fireplace/widgets/message/video_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _videoMessage({String content = ''}) => MessageModel(
  id: 7,
  content: content,
  senderId: 1,
  senderUsername: 'alice',
  conversationId: 10,
  deliveryStatus: MessageDeliveryStatus.read,
  messageType: MessageType.video,
  createdAt: DateTime(2026, 1, 1, 14, 30),
  mediaUrl: 'https://example.com/media/msgs/v.bin',
  mediaDuration: 12,
  encryptedContent: 'cipher',
);

void main() {
  group('VIDEO wire parsing', () {
    test('fromJson parses messageType VIDEO round-trip', () {
      final msg = MessageModel.fromJson(const {
        'id': 1,
        'content': '',
        'senderId': 1,
        'senderUsername': 'alice',
        'conversationId': 10,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'messageType': 'VIDEO',
        'mediaUrl': 'https://example.com/media/msgs/v.bin',
        'mediaDuration': 12,
      });

      expect(msg.messageType, MessageType.video);
      expect(msg.mediaDuration, 12);
      // Round-trip: the enum name is what the send path puts back on the wire.
      expect(msg.messageType.name.toUpperCase(), 'VIDEO');
    });

    test('copyWith preserves video type and media fields', () {
      final copy = _videoMessage().copyWith(content: 'x');
      expect(copy.messageType, MessageType.video);
      expect(copy.mediaUrl, 'https://example.com/media/msgs/v.bin');
      expect(copy.mediaDuration, 12);
    });
  });

  group('video reply preview label', () {
    test('replyPreviewForMessageModel shows video label for encrypted VIDEO row', () {
      const labels = kReplyPreviewLabels;
      final preview = replyPreviewForMessageModel(
        _videoMessage(content: 'Encrypted message'),
        encryption: null,
        encryptedMessageLabel: labels.encryptedMessageLabel,
        voiceMessageLabel: labels.voiceMessageLabel,
        imageLabel: labels.imageLabel,
        gifLabel: labels.gifLabel,
        documentLabel: labels.documentLabel,
        pingLabel: labels.pingLabel,
        videoLabel: labels.videoLabel,
      );
      expect(preview, labels.videoLabel);
      expect(preview, isNotEmpty);
    });
  });

  group('MessageContentFactory video case', () {
    testWidgets('returns VideoMessageContent for a video message', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => MessageContentFactory.build(
                context: context,
                message: _videoMessage(),
                isMine: false,
                isDark: false,
                textColor: Colors.black,
                contentAreaWidth: 300,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(VideoMessageContent), findsOneWidget);
    });
  });
}
