import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/recording_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: RpgTheme.themeDataLight,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

ConversationsProvider _conversationsWithActiveChat() {
  final provider = ConversationsProvider();
  provider.setCurrentUserId(1);
  provider.onConversationsList([
    {
      'id': 10,
      'userOne': {'id': 1, 'username': 'alice', 'tag': '0001'},
      'userTwo': {'id': 2, 'username': 'bob', 'tag': '0002'},
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'unreadCount': 0,
    },
  ]);
  provider.openConversation(10);
  return provider;
}

Widget _wrapWithMessagingProviders(Widget child) {
  final convs = _conversationsWithActiveChat();
  final messaging = MessagingProvider()
    ..setConversationsProvider(convs)
    ..setCurrentUserId(1)
    ..onConnect(false)
    ..setIncomingMessageSoundEnabledForTest(false);
  return MaterialApp(
    theme: RpgTheme.themeDataLight,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: MultiProvider(
        providers: [
          ChangeNotifierProvider<ConversationsProvider>.value(value: convs),
          ChangeNotifierProvider<MessagingProvider>.value(value: messaging),
          ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ],
        child: child,
      ),
    ),
  );
}

/// Keeps [RecordingController] mounted while rendering its recording bar for UI tests.
class _RecordingBarHarness extends StatefulWidget {
  const _RecordingBarHarness({
    required this.recordingKey,
    this.locked = false,
  });

  final GlobalKey<RecordingControllerState> recordingKey;
  final bool locked;

  @override
  State<_RecordingBarHarness> createState() => _RecordingBarHarnessState();
}

class _RecordingBarHarnessState extends State<_RecordingBarHarness> {
  @override
  Widget build(BuildContext context) {
    final state = widget.recordingKey.currentState;
    return Column(
      children: [
        RecordingController(
          key: widget.recordingKey,
          onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
          onRecordingStateChanged: (_) => setState(() {}),
          onRecordingBarChanged: () => setState(() {}),
          isSendingVoice: false,
        ),
        if (state != null && state.isRecording)
          widget.locked
              ? state.buildRecordingBarLocked(context)
              : state.buildRecordingBar(context),
      ],
    );
  }
}

void main() {
  group('RecordingController lock-up (chunk 1.1)', () {
    testWidgets('slide up past threshold sets isLocked', (tester) async {
      late RecordingControllerState recordingState;

      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      recordingState = tester.state(find.byType(RecordingController));
      recordingState.simulateActiveRecordingForTest(startX: 100, startY: 200);
      await tester.pump();

      expect(recordingState.isLocked, isFalse);

      recordingState.simulateDragUpdateForTest(100, 200 - 80);
      await tester.pump();

      expect(recordingState.isLocked, isTrue);
      expect(recordingState.lockDragOffset, RecordingControllerState.lockUpThresholdPx);
    });

    testWidgets('71px upward drag does not lock; 72px locks', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateActiveRecordingForTest(startX: 100, startY: 200);
      await tester.pump();

      recordingState.simulateDragUpdateForTest(100, 200 - 71);
      await tester.pump();
      expect(recordingState.isLocked, isFalse);
      expect(recordingState.lockDragOffset, 71);

      recordingState.simulateDragUpdateForTest(100, 200 - 72);
      await tester.pump();
      expect(recordingState.isLocked, isTrue);
    });

    testWidgets('release after lock does not finish gesture', (tester) async {
      var recordingActive = true;

      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (active) => recordingActive = active,
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateActiveRecordingForTest(startX: 100, startY: 200);
      recordingState.simulateDragUpdateForTest(100, 200 - 80);
      await tester.pump();

      expect(recordingState.isLocked, isTrue);

      recordingState.simulateGestureFinishForTest();
      await tester.pump();

      expect(recordingState.isRecording, isTrue);
      expect(recordingActive, isTrue);
    });

    testWidgets('Listener pointer up after lock continues recording', (tester) async {
      var recordingActive = true;

      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (active) => recordingActive = active,
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateActiveRecordingForTest(startX: 100, startY: 200);
      recordingState.simulateDragUpdateForTest(100, 200 - 72);
      await tester.pump();

      expect(recordingState.isLocked, isTrue);

      recordingState.simulatePointerReleaseForTest();
      await tester.pump();

      expect(recordingState.isRecording, isTrue);
      expect(recordingState.isLocked, isTrue);
      expect(recordingActive, isTrue);
    });

    testWidgets('second long-press while locked is ignored', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateActiveRecordingForTest(startX: 100, startY: 200);
      recordingState.simulateDragUpdateForTest(100, 200 - 72);
      await tester.pump();

      expect(recordingState.isLocked, isTrue);

      recordingState.simulateLongPressStartForTest(50, 50);
      await tester.pump();

      expect(recordingState.isLocked, isTrue);
      expect(recordingState.isRecording, isTrue);
    });

    testWidgets('horizontal slide-left cancel unchanged while unlocked',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateActiveRecordingForTest(startX: 300, startY: 200);
      recordingState.simulateDragUpdateForTest(100, 200);
      await tester.pump();

      expect(recordingState.isLocked, isFalse);
      expect(recordingState.cancelDragOffset, lessThan(-150));
      expect(recordingState.isRecording, isTrue);
    });
  });

  group('RecordingController lock-up UI (chunk 1.2)', () {
    testWidgets('onRecordingLockChanged fires on lock transition', (tester) async {
      var lockChanged = false;
      var lockedValue = false;

      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            onRecordingLockChanged: (locked) {
              lockChanged = true;
              lockedValue = locked;
            },
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateActiveRecordingForTest(startX: 100, startY: 200);
      recordingState.simulateDragUpdateForTest(100, 200 - 72);
      await tester.pump();

      expect(lockChanged, isTrue);
      expect(lockedValue, isTrue);
    });

    testWidgets('unlocked bar shows slide-up hint after 36px drag', (tester) async {
      final recordingKey = GlobalKey<RecordingControllerState>();

      await tester.pumpWidget(
        _wrap(_RecordingBarHarness(recordingKey: recordingKey)),
      );

      recordingKey.currentState!.simulateActiveRecordingForTest(startX: 100, startY: 200);
      await tester.pump();

      expect(find.text('← Slide to cancel'), findsOneWidget);
      expect(find.text('↑ Slide up to lock'), findsNothing);

      recordingKey.currentState!.simulateDragUpdateForTest(100, 200 - 40);
      await tester.pump();

      expect(find.text('↑ Slide up to lock'), findsOneWidget);
    });

    testWidgets('locked bar shows cancel, lock label, and timer', (tester) async {
      final recordingKey = GlobalKey<RecordingControllerState>();

      await tester.pumpWidget(
        _wrap(_RecordingBarHarness(recordingKey: recordingKey, locked: true)),
      );

      recordingKey.currentState!.simulateActiveRecordingForTest(startX: 100, startY: 200);
      recordingKey.currentState!.simulateDragUpdateForTest(100, 200 - 72);
      await tester.pump();

      expect(find.text('Locked — tap Send when done'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
    });
  });

  group('RecordingController lock-up API (chunk 1.3)', () {
    testWidgets('simulateLockedRecordingForTest sets isLocked', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateLockedRecordingForTest();
      await tester.pump();

      expect(recordingState.isRecording, isTrue);
      expect(recordingState.isLocked, isTrue);
    });

    testWidgets('sendLockedRecording no-op when unlocked', (tester) async {
      var recordingActive = true;

      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (active) => recordingActive = active,
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateActiveRecordingForTest();
      await tester.pump();

      recordingState.sendLockedRecording();
      await tester.pump();

      expect(recordingState.isRecording, isTrue);
      expect(recordingActive, isTrue);
    });

    testWidgets('sendLockedRecording without recorder keeps session active',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateLockedRecordingForTest();
      await tester.pump();

      recordingState.sendLockedRecording();
      await tester.pump();

      expect(recordingState.isRecording, isTrue);
      expect(recordingState.isLocked, isTrue);
    });

    testWidgets('cancelLockedRecording without recorder keeps session active',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.simulateLockedRecordingForTest();
      await tester.pump();

      recordingState.cancelLockedRecording();
      await tester.pump();

      expect(recordingState.isRecording, isTrue);
      expect(recordingState.isLocked, isTrue);
    });

    testWidgets('unlocked release sends voice when testSkipHardware',
        (tester) async {
      var voiceSent = false;

      await tester.pumpWidget(
        _wrapWithMessagingProviders(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {
              voiceSent = true;
            },
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.testSkipHardware = true;
      recordingState.simulateActiveRecordingForTest(
        elapsed: const Duration(milliseconds: 600),
      );
      recordingState.simulateGestureFinishForTest();
      await tester.pump();

      expect(voiceSent, isTrue);
      expect(recordingState.isRecording, isFalse);
    });

    testWidgets('locked send under 500ms shows hold-longer snackbar',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithMessagingProviders(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.testSkipHardware = true;
      recordingState.simulateLockedRecordingForTest();
      await tester.pump();

      recordingState.sendLockedRecording();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Hold longer to record a voice message'), findsOneWidget);
      expect(recordingState.isRecording, isFalse);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('cancelLockedRecording with testSkipHardware ends session',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithMessagingProviders(
          RecordingController(
            onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
            onRecordingStateChanged: (_) {},
            isSendingVoice: false,
          ),
        ),
      );

      final recordingState = tester.state<RecordingControllerState>(
        find.byType(RecordingController),
      );
      recordingState.testSkipHardware = true;
      recordingState.simulateLockedRecordingForTest();
      await tester.pump();

      recordingState.cancelLockedRecording();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Voice recording canceled'), findsOneWidget);
      expect(recordingState.isRecording, isFalse);
      expect(recordingState.isLocked, isFalse);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
