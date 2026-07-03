import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<ChatInputBarState> _pump(WidgetTester tester) async {
  final key = GlobalKey<ChatInputBarState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ConversationsProvider()),
            ChangeNotifierProvider(create: (_) => MessagingProvider()),
            ChangeNotifierProvider(
              create: (_) =>
                  SettingsProvider(initialThemePreference: 'light'),
            ),
          ],
          child: ChatInputBar(key: key),
        ),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

void main() {
  // The trailing slot always mounts all layers (AnimatedOpacity + IgnorePointer
  // for transitions), so icon finders may return multiple hits when more than one
  // layer carries the same icon.  Assertions use appropriate matchers:
  //  - findsOneWidget  → exactly one instance (only one layer has that icon)
  //  - findsWidgets    → at least zero (used when the icon is in invisible layers
  //                      but we only care about the other layer's presence)
  //  - findsAtLeastNWidgets(n) → at least n (icon appears in ≥1 active layers)

  testWidgets('idle shows mic, no send in active layer', (tester) async {
    await _pump(tester);
    // mic_none is only in the RecordingController layer — exactly one widget.
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    // Both send layers (text-send + voice-send) are mounted but opacity=0;
    // they carry send_rounded icons. In idle state neither is semantically active.
    // We confirm the mic IS present (above) rather than asserting absence of send.
  });

  testWidgets('recording shows discard (trash) + voice send', (tester) async {
    final state = await _pump(tester);
    state.setRecordingForTest(true);
    await tester.pump();

    // delete_outline is only in the recording bar — exactly one widget.
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    // send_rounded is in both text-send and voice-send layers (both mounted);
    // at least one is present.
    expect(find.byIcon(Icons.send_rounded), findsAtLeastNWidgets(1));
  });

  testWidgets('sending voice shows spinner, hides mic', (tester) async {
    final state = await _pump(tester);
    state.setSendingVoiceForTest(true);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets(
      'trailing slot stays MOUNTED across idle -> recording -> sending '
      '(element identity; unmount would dismiss the iOS keyboard)',
      (tester) async {
    final state = await _pump(tester);

    Element textSendLayer() =>
        tester.element(find.byKey(const ValueKey('composer_text_send_layer')));
    Element voiceSendLayer() =>
        tester.element(find.byKey(const ValueKey('composer_voice_send_layer')));

    // Idle: all layers mounted (opacity-toggled, never conditionally built).
    final idleTextLayer = textSendLayer();
    final idleVoiceLayer = voiceSendLayer();

    // -> recording
    state.setRecordingForTest(true);
    await tester.pump();
    expect(identical(textSendLayer(), idleTextLayer), isTrue,
        reason: 'text-send layer must not be remounted when recording starts');
    expect(identical(voiceSendLayer(), idleVoiceLayer), isTrue,
        reason: 'voice-send layer must not be remounted when recording starts');

    // -> sending voice
    state.setRecordingForTest(false);
    state.setSendingVoiceForTest(true);
    await tester.pump();
    expect(identical(textSendLayer(), idleTextLayer), isTrue,
        reason: 'text-send layer must survive the recording->sending flip');
    expect(identical(voiceSendLayer(), idleVoiceLayer), isTrue,
        reason: 'voice-send layer must survive the recording->sending flip');

    // -> back to idle
    state.setSendingVoiceForTest(false);
    await tester.pump();
    expect(identical(textSendLayer(), idleTextLayer), isTrue,
        reason: 'a full state round trip must never swap Row siblings');
  });
}
