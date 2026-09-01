import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/utils/reply_preview_helper.dart';
import 'package:fireplace/widgets/message/media_preview_frame.dart';
import 'package:fireplace/widgets/message/message_content_factory.dart';
import 'package:fireplace/widgets/message/video_message_content.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

MessageModel _videoMessage({
  String content = '',
  int? mediaWidth,
  int? mediaHeight,
  String? mediaThumbHash,
  String? mediaUrl = 'https://example.com/media/msgs/v.bin',
}) => MessageModel(
  id: 7,
  content: content,
  senderId: 1,
  senderUsername: 'alice',
  conversationId: 10,
  deliveryStatus: MessageDeliveryStatus.read,
  messageType: MessageType.video,
  createdAt: DateTime(2026, 1, 1, 14, 30),
  mediaUrl: mediaUrl,
  mediaDuration: 12,
  mediaWidth: mediaWidth,
  mediaHeight: mediaHeight,
  mediaThumbHash: mediaThumbHash,
  encryptedContent: 'cipher',
);

Future<void> _pumpBubble(WidgetTester tester, MessageModel message) {
  // Providers sit ABOVE MaterialApp: the fullscreen viewer is a dialog pushed
  // on the root navigator, so anything below MaterialApp is out of its scope.
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
          value: AuthProvider()..setAccessTokenForTest('tok'),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Center(
            // ConstrainedBox, not SizedBox: a real bubble gets a LOOSE max
            // width, and a tight one would forbid the frame from narrowing to
            // preserve a portrait ratio.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: VideoMessageContent(message: message),
            ),
          ),
        ),
      ),
    ),
  );
}

Size _frameSize(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('media_preview_frame')));

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

  group('video bubble geometry', () {
    testWidgets('sizes the frame to the envelope aspect ratio', (tester) async {
      // Portrait 360x480 (what iOS HTML Media Capture actually produces).
      await _pumpBubble(
        tester,
        _videoMessage(mediaWidth: 360, mediaHeight: 480),
      );

      final size = _frameSize(tester);
      // The contract is the RATIO, not fixed pixels: the frame clamps height
      // to 52% of the viewport (600 * 0.52 = 312 here), then re-derives width
      // from the ratio, so asserting 300x400 would pin the clamp, not the fix.
      expect(size.width / size.height, closeTo(360 / 480, 0.01));
      // The defect being fixed: a portrait clip must NOT land on the fixed
      // legacy height, which is what produced the letterboxed side bars.
      expect(size.height, isNot(closeTo(MediaPreviewFrame.legacyHeight, 0.5)));
      expect(size.height, greaterThan(size.width));
    });

    testWidgets('falls back to the legacy height without geometry', (
      tester,
    ) async {
      // Videos sent before geometry existed in the envelope. Upgrade-only:
      // they must keep rendering, just not aspect-correct.
      await _pumpBubble(tester, _videoMessage());

      final size = _frameSize(tester);
      expect(size.height, closeTo(MediaPreviewFrame.legacyHeight, 0.5));
    });

    testWidgets('holds no video controller and fetches nothing', (
      tester,
    ) async {
      await _pumpBubble(
        tester,
        _videoMessage(mediaWidth: 360, mediaHeight: 480),
      );

      // The bubble is a static poster by design: a scrolling list must never
      // hold N live players or N decrypted multi-megabyte buffers.
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tap opens the fullscreen viewer', (tester) async {
      await _pumpBubble(
        tester,
        _videoMessage(mediaWidth: 360, mediaHeight: 480),
      );

      await tester.tap(find.byType(VideoMessageContent));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('video_fullscreen_close')),
        findsOneWidget,
      );
    });
  });

  group('fullscreen viewer failure states', () {
    // An optimistic bubble is tappable while its blob is still uploading, so
    // this branch is reachable by the SENDER on their own message. It must not
    // accuse the app of a decryption failure: nothing has been decrypted yet.
    testWidgets('still-uploading video reports sending, not failure', (
      tester,
    ) async {
      await _pumpBubble(tester, _videoMessage(mediaUrl: null));

      await tester.tap(find.byType(VideoMessageContent));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Still sending…'), findsOneWidget);
      expect(find.text('Video failed to load'), findsNothing);
      expect(find.text('Decryption failed'), findsNothing);
    });

    // loadDecryptedMediaBytes throws ONE exception for fetch/oversize/decrypt
    // alike, so the copy stays neutral rather than naming a cause it cannot
    // know. Test HTTP is stubbed to fail, which lands in the same catch.
    testWidgets('unreachable media reports a neutral load failure', (
      tester,
    ) async {
      await _pumpBubble(tester, _videoMessage());

      await tester.tap(find.byType(VideoMessageContent));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Video failed to load'), findsOneWidget);
      expect(find.text('Decryption failed'), findsNothing);
    });
  });
}
