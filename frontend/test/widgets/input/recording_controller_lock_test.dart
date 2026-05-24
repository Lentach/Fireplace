import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/widgets/input/recording_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
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

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => recordingState.buildRecordingBar(context),
          ),
        ),
      );
      expect(find.text('← Slide to cancel'), findsOneWidget);
      expect(find.text('↑ Slide up to lock'), findsNothing);

      recordingState.simulateDragUpdateForTest(100, 200 - 40);
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => recordingState.buildRecordingBar(context),
          ),
        ),
      );
      expect(find.text('↑ Slide up to lock'), findsOneWidget);
    });

    testWidgets('locked bar shows cancel, lock label, and timer', (tester) async {
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

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => recordingState.buildRecordingBarLocked(context),
          ),
        ),
      );

      expect(find.text('Locked — tap Send when done'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
    });
  });
}
