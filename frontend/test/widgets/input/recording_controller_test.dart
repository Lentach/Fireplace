import 'dart:typed_data';

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/widgets/input/recording_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Helper: pump a RecordingController with localization AND the providers it
// reads from context (stopAndSend/cancelRecording call context.read<...>()).
// activeConversationId stays null, so _emitRecordingVoiceToRecipient no-ops.
Future<RecordingControllerState> _pumpController(
  WidgetTester tester, {
  required Future<void> Function({
    required int duration,
    String? localAudioPath,
    Uint8List? audioBytes,
  }) onVoiceSent,
  required void Function(bool) onRecordingStateChanged,
}) async {
  final key = GlobalKey<RecordingControllerState>();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => ConversationsProvider()),
        ChangeNotifierProvider(create: (_) => MessagingProvider()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RecordingController(
            key: key,
            onVoiceSent: onVoiceSent,
            onRecordingStateChanged: onRecordingStateChanged,
            onMicTap: () {},
            isSendingVoice: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

void main() {
  group('RecordingControllerState', () {
    test('kMinVoiceRecordingMs is 500ms from actual recording start', () {
      expect(RecordingControllerState.kMinVoiceRecordingMs, 500);
    });
  });

  group('MicRecordingPermissionDenied', () {
    test('is distinct from generic Exception for start-recording catch', () {
      expect(const MicRecordingPermissionDenied(), isA<Exception>());
      expect(const MicRecordingPermissionDenied(), isNot(isA<StateError>()));
    });
  });

  group('RecordingController tap model', () {
    testWidgets('stopAndSend after >=500ms calls onVoiceSent once',
        (tester) async {
      var sent = 0;
      int? sentDuration;
      final state = await _pumpController(
        tester,
        onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {
          sent++;
          sentDuration = duration;
        },
        onRecordingStateChanged: (_) {},
      );
      state.testSkipHardware = true;
      state.simulateRecordingForTest(elapsed: const Duration(seconds: 3));
      await tester.pump();

      await state.stopAndSend();
      await tester.pump();

      expect(sent, 1);
      // Duration uses ceiling rounding ((ms+999)~/1000); wall-clock between
      // simulate and stop pushes elapsed just past 3000ms, so it rounds to 4.
      expect(sentDuration, greaterThanOrEqualTo(3));
      expect(state.isRecording, isFalse);
    });

    testWidgets('stopAndSend under 500ms discards silently (no onVoiceSent)',
        (tester) async {
      var sent = 0;
      final state = await _pumpController(
        tester,
        onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {
          sent++;
        },
        onRecordingStateChanged: (_) {},
      );
      state.testSkipHardware = true;
      state.simulateRecordingForTest(elapsed: Duration.zero);
      await tester.pump();

      await state.stopAndSend();
      await tester.pump();

      expect(sent, 0);
      expect(state.isRecording, isFalse);
    });

    testWidgets('cancelRecording discards, no onVoiceSent', (tester) async {
      var sent = 0;
      final state = await _pumpController(
        tester,
        onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {
          sent++;
        },
        onRecordingStateChanged: (_) {},
      );
      state.testSkipHardware = true;
      state.simulateRecordingForTest(elapsed: const Duration(seconds: 3));
      await tester.pump();

      await state.cancelRecording();
      // cancelRecording shows a top snackbar (Future.delayed 2500ms auto-dismiss);
      // pump past it so no timer is pending at teardown.
      await tester.pump(const Duration(milliseconds: 2600));

      expect(sent, 0);
      expect(state.isRecording, isFalse);
    });

    testWidgets('stopAndSend then immediate cancel sends at most once',
        (tester) async {
      var sent = 0;
      final state = await _pumpController(
        tester,
        onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {
          sent++;
        },
        onRecordingStateChanged: (_) {},
      );
      state.testSkipHardware = true;
      state.simulateRecordingForTest(elapsed: const Duration(seconds: 3));
      await tester.pump();

      final f1 = state.stopAndSend();
      final f2 = state.cancelRecording();
      await Future.wait([f1, f2]);
      await tester.pump();

      expect(sent, lessThanOrEqualTo(1));
      expect(state.isRecording, isFalse);
    });

    testWidgets('startRecording is a no-op while already starting',
        (tester) async {
      final state = await _pumpController(
        tester,
        onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
        onRecordingStateChanged: (_) {},
      );
      state.debugSetStartingForTest(true);
      await state.startRecording(); // must return immediately
      expect(state.isRecording, isFalse);
    });
  });
}
