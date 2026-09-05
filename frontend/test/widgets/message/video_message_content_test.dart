import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/widgets/message/inline_video_arbiter.dart';
import 'package:fireplace/widgets/message/video_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

/// Counts slot traffic so tests can assert the bubble's arbiter behaviour
/// without a live [VideoPlayerController].
class _RecordingArbiter extends InlineVideoArbiter {
  _RecordingArbiter() : super.forTest();

  int requests = 0;

  @override
  void request(Object owner, VoidCallback onRevoke) {
    requests++;
    super.request(owner, onRevoke);
  }
}

MessageModel _videoMessage({String? mediaUrl}) => MessageModel(
  id: 7,
  content: '',
  senderId: 1,
  senderUsername: 'alice',
  conversationId: 10,
  deliveryStatus: MessageDeliveryStatus.read,
  messageType: MessageType.video,
  createdAt: DateTime(2026, 1, 1, 14, 30),
  mediaUrl: mediaUrl,
  mediaDuration: 12,
  mediaWidth: 360,
  mediaHeight: 480,
  encryptedContent: 'cipher',
);

Future<void> _pumpBubble(
  WidgetTester tester,
  MessageModel message, {
  SettingsProvider? settings,
  InlineVideoArbiter? arbiter,
}) {
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: VideoMessageContent(message: message, arbiter: arbiter),
        ),
      ),
    ),
  );
  return tester.pumpWidget(
    settings == null
        ? app
        : ChangeNotifierProvider<SettingsProvider>.value(
            value: settings,
            child: app,
          ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('without a SettingsProvider the bubble is a static poster', (
    tester,
  ) async {
    final arbiter = _RecordingArbiter();
    await _pumpBubble(tester, _videoMessage(mediaUrl: 'https://x/v.bin'),
        arbiter: arbiter);
    await tester.pump();

    // No provider in the tree means autoplay OFF — poster + play badge, no
    // inline player, no mute control, and the arbiter is never bothered.
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('video_inline_mute_toggle')), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(arbiter.requests, 0);
  });

  testWidgets(
    'autoplay ON but still-sending (no uploaded blob) never requests the slot',
    (tester) async {
      final arbiter = _RecordingArbiter();
      await _pumpBubble(
        tester,
        _videoMessage(mediaUrl: null),
        settings: SettingsProvider(), // autoplayVideos defaults true
        arbiter: arbiter,
      );
      await tester.pump();
      await tester.pump();

      expect(arbiter.requests, 0);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
    },
  );

  testWidgets(
    'visible autoplay bubble requests the slot; a failed load falls back to '
    'the poster silently and releases it',
    (tester) async {
      final arbiter = _RecordingArbiter();
      await _pumpBubble(
        tester,
        _videoMessage(mediaUrl: 'https://example.com/media/msgs/v.bin'),
        settings: SettingsProvider(),
        arbiter: arbiter,
      );
      // Post-frame visibility check → arbiter request → load; test HTTP is
      // stubbed to fail, so the load lands in the silent-fallback branch.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(arbiter.requests, 1);
      // Silent fallback: poster restored, slot given back, no error copy.
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.text('Video failed to load'), findsNothing);
      expect(
        find.byKey(const ValueKey('video_inline_mute_toggle')),
        findsNothing,
      );
      expect(arbiter.holds(tester.state(find.byType(VideoMessageContent))),
          isFalse);
    },
  );
}
