import 'dart:ui' as ui;

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:fireplace/widgets/input/recording_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

ConversationsProvider _providerWithConversation({required int conversationId}) {
  final userA = UserModel(id: 1, username: 'alice', tag: '0001');
  final userB = UserModel(id: 2, username: 'bob', tag: '0002');
  final provider = ConversationsProvider();
  provider.setCurrentUserId(1);
  provider.onConversationsList([
    {
      'id': conversationId,
      'userOne': {'id': userA.id, 'username': userA.username, 'tag': userA.tag},
      'userTwo': {'id': userB.id, 'username': userB.username, 'tag': userB.tag},
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'unreadCount': 0,
    },
  ]);
  provider.openConversation(conversationId);
  return provider;
}

MessagingProvider _messagingLinkedTo(ConversationsProvider convs) {
  final messaging = MessagingProvider()
    ..setIncomingMessageSoundEnabledForTest(false);
  messaging.setConversationsProvider(convs);
  messaging.setCurrentUserId(1);
  messaging.onConnect(false);
  return messaging;
}

Future<void> _pumpChatInputBar(
  WidgetTester tester, {
  required ConversationsProvider convs,
  required MessagingProvider messaging,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: RpgTheme.themeDataLight,
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<ConversationsProvider>.value(value: convs),
            ChangeNotifierProvider<MessagingProvider>.value(value: messaging),
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(initialThemePreference: 'light'),
            ),
            ChangeNotifierProvider(create: (_) => ConnectionProvider()),
          ],
          child: const ChatInputBar(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _micSlotFinder() => find.byKey(const ValueKey('composer_mic_slot'));
Finder _sendSlotFinder() => find.byKey(const ValueKey('composer_send_slot'));
Finder _micOpacityFinder() => find.byKey(const ValueKey('composer_mic_layer'));
Finder _textSendActionFinder() =>
    find.byKey(const ValueKey('composer_text_send_action'));
Finder _voiceSendActionFinder() =>
    find.byKey(const ValueKey('composer_voice_send_action'));
Finder _sendSpinnerFinder() =>
    find.byKey(const ValueKey('composer_send_spinner'));

IgnorePointer _micIgnorePointer(WidgetTester tester) {
  return tester.widget<IgnorePointer>(
    find.descendant(of: _micSlotFinder(), matching: find.byType(IgnorePointer)),
  );
}

void main() {
  group('ChatInputBar trailing send', () {
    late ConversationsProvider convs;
    late MessagingProvider messaging;
    setUp(() {
      convs = _providerWithConversation(conversationId: 10);
      messaging = _messagingLinkedTo(convs);
    });

    testWidgets('empty draft keeps mic enabled and send visible', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      expect(find.byType(RecordingController), findsOneWidget);
      expect(_textSendActionFinder(), findsOneWidget);
      expect(_voiceSendActionFinder(), findsNothing);
      expect(_sendSpinnerFinder(), findsNothing);

      final micOpacity = tester.widget<AnimatedOpacity>(_micOpacityFinder());
      expect(micOpacity.opacity, 1);
      expect(_micIgnorePointer(tester).ignoring, isFalse);
    });

    testWidgets(
      'non-empty draft disables mic but keeps send affordance visible',
      (tester) async {
        await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

        await tester.enterText(find.byType(TextField), 'hi');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 175));

        expect(_textSendActionFinder(), findsOneWidget);
        expect(_voiceSendActionFinder(), findsNothing);
        expect(_sendSpinnerFinder(), findsNothing);

        final micOpacity = tester.widget<AnimatedOpacity>(_micOpacityFinder());
        expect(micOpacity.opacity, lessThan(1));
        expect(_micIgnorePointer(tester).ignoring, isTrue);
      },
    );

    testWidgets('whitespace-only draft keeps mic enabled and send visible', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(_textSendActionFinder(), findsOneWidget);
      expect(_micIgnorePointer(tester).ignoring, isFalse);
    });

    testWidgets('trailing actions keep mic left and send right', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final micCenter = tester.getCenter(_micSlotFinder());
      final sendCenter = tester.getCenter(_sendSlotFinder());
      expect(micCenter.dx, lessThan(sendCenter.dx));
    });

    testWidgets('send icon is centered in right 48x48 slot', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final sendSlotCenter = tester.getCenter(_sendSlotFinder());
      final sendIconCenter = tester.getCenter(
        find
            .descendant(
              of: _sendSlotFinder(),
              matching: find.byIcon(Icons.send_rounded),
            )
            .first,
      );
      expect((sendSlotCenter.dx - sendIconCenter.dx).abs(), lessThan(0.01));
      expect((sendSlotCenter.dy - sendIconCenter.dy).abs(), lessThan(0.01));
    });

    testWidgets(
      'text send action stays tap-only (no IconButton in text state)',
      (tester) async {
        await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

        expect(
          find.descendant(
            of: _textSendActionFinder(),
            matching: find.byType(IconButton),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: _textSendActionFinder(),
            matching: find.byType(Listener),
          ),
          findsWidgets,
        );
      },
    );

    testWidgets('tap send with empty draft is no-op', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(messaging.messages, isEmpty);
    });

    testWidgets('tap send calls sendMessage and clears field', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(messaging.messages, isEmpty);

      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(messaging.messages.length, 1);
      expect(messaging.messages.first.content, 'hello');
      expect(find.text('hello'), findsNothing);
    });

    testWidgets('text send exposes semantic tap action and can send', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpChatInputBar(tester, convs: convs, messaging: messaging);
        await tester.enterText(find.byType(TextField), 'semantic send');
        await tester.pump();

        final semanticsFinder = find.bySemanticsLabel('Send message');
        expect(semanticsFinder, findsOneWidget);
        expect(
          tester
              .getSemantics(semanticsFinder)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isTrue,
        );

        await tester.tap(semanticsFinder);
        await tester.pump();

        expect(messaging.messages.length, 1);
        expect(messaging.messages.first.content, 'semantic send');
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('IME TextInputAction.send calls sendMessage', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), 'ime send');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(messaging.messages.length, 1);
      expect(messaging.messages.first.content, 'ime send');
    });

    testWidgets('Ctrl+Enter sends message via CallbackShortcuts', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), 'shortcut send');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(messaging.messages.length, 1);
      expect(messaging.messages.first.content, 'shortcut send');
    });

    testWidgets('TapRegion wraps TextField and trailing stack', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final tapRegion = find.descendant(
        of: find.byType(ChatInputBar),
        matching: find.byType(TapRegion),
      );
      expect(tapRegion, findsOneWidget);

      expect(
        find.descendant(of: tapRegion, matching: find.byType(TextField)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tapRegion,
          matching: find.byType(RecordingController),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tapRegion, matching: _sendSlotFinder()),
        findsOneWidget,
      );
    });

    testWidgets('composer TapRegion groupId is stable across rebuilds', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final tapRegion = find.descendant(
        of: find.byType(ChatInputBar),
        matching: find.byType(TapRegion),
      );

      final groupBefore = tester.widget<TapRegion>(tapRegion).groupId;

      await tester.enterText(find.byType(TextField), 'rebuild');
      await tester.pump();

      final groupAfter = tester.widget<TapRegion>(tapRegion).groupId;
      expect(identical(groupBefore, groupAfter), isTrue);
    });

    testWidgets('pointerDown on send retains focus before pointerUp', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.pump();

      final focusNode = tester.widget<TextField>(textField).focusNode!;
      focusNode.unfocus();
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);

      final sendCenter = tester.getCenter(find.byTooltip('Send'));
      final gesture = await tester.startGesture(sendCenter);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('after send focus is retained or restored post-frame', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.pump();
      await tester.enterText(textField, 'hi');
      await tester.pump();

      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      final focusNode = tester.widget<TextField>(textField).focusNode;
      expect(focusNode?.hasFocus, isTrue);
    });

    testWidgets('RecordingController stays mounted while typing', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      expect(find.byType(RecordingController), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();

      expect(find.byType(RecordingController), findsOneWidget);
    });

    testWidgets('text send affordance remains in right slot while recording', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final barState = tester.state<ChatInputBarState>(
        find.byType(ChatInputBar),
      );
      barState.setRecordingForTest(true);
      await tester.pump();

      expect(_textSendActionFinder(), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('sending voice shows spinner and disables both actions', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final barState = tester.state<ChatInputBarState>(
        find.byType(ChatInputBar),
      );
      barState.setSendingVoiceForTest(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(_sendSpinnerFinder(), findsOneWidget);
      expect(_textSendActionFinder(), findsNothing);
      expect(_voiceSendActionFinder(), findsNothing);
      expect(_micIgnorePointer(tester).ignoring, isTrue);
    });

    testWidgets('right-slot priority prefers spinner over locked voice send', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final barState = tester.state<ChatInputBarState>(
        find.byType(ChatInputBar),
      );
      barState.setRecordingForTest(true);
      barState.setRecordingLockedForTest(true);
      barState.setSendingVoiceForTest(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(_sendSpinnerFinder(), findsOneWidget);
      expect(_voiceSendActionFinder(), findsNothing);
      expect(_textSendActionFinder(), findsNothing);
    });

    testWidgets('send has localized tooltip when visible', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

        await tester.enterText(find.byType(TextField), 'hi');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 175));

        expect(find.byTooltip('Send'), findsOneWidget);
        expect(find.bySemanticsLabel('Send message'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Send message'))
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    });

    group('TextInput.show gating', () {
      var textInputShowInvocationCount = 0;

      Future<void> withTextInputShowMock(
        WidgetTester tester,
        Future<void> Function() body,
      ) async {
        textInputShowInvocationCount = 0;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
              if (call.method == 'TextInput.show') {
                textInputShowInvocationCount++;
              }
              return null;
            });
        try {
          await body();
        } finally {
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.textInput, null);
          debugDefaultTargetPlatformOverride = null;
        }
      }

      testWidgets(
        'trailing send with focus held does not invoke TextInput.show',
        (tester) async {
          await withTextInputShowMock(tester, () async {
            await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

            final textField = find.byType(TextField);
            await tester.tap(textField);
            await tester.pump();
            await tester.enterText(textField, 'hi');
            await tester.pump();

            textInputShowInvocationCount = 0;
            await tester.tap(find.byTooltip('Send'));
            await tester.pump();
            await tester.pump();

            expect(textInputShowInvocationCount, 0);
          });
        },
      );

      testWidgets('_send after focus lost may invoke TextInput.show', (
        tester,
      ) async {
        await withTextInputShowMock(tester, () async {
          await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

          final textField = find.byType(TextField);
          await tester.enterText(textField, 'hi');
          await tester.pump();

          final barState = tester.state<ChatInputBarState>(
            find.byType(ChatInputBar),
          );
          final focusNode = tester.widget<TextField>(textField).focusNode!;
          focusNode.unfocus();
          await tester.pump();
          expect(focusNode.hasFocus, isFalse);

          textInputShowInvocationCount = 0;
          barState.sendMessageForTest();
          await tester.pump();
          await tester.pump();

          expect(textInputShowInvocationCount, greaterThan(0));
        });
      });
    });
  });

  group('ChatInputBar voice lock trailing send (chunk 1.3)', () {
    late ConversationsProvider convs;
    late MessagingProvider messaging;

    setUp(() {
      convs = _providerWithConversation(conversationId: 10);
      messaging = _messagingLinkedTo(convs);
    });

    testWidgets(
      'locked recording shows voice send and hides text send with draft',
      (tester) async {
        await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

        await tester.enterText(find.byType(TextField), 'draft text');
        await tester.pump();

        final barState = tester.state<ChatInputBarState>(
          find.byType(ChatInputBar),
        );
        barState.setRecordingForTest(true);
        barState.setRecordingLockedForTest(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(_voiceSendActionFinder(), findsOneWidget);
        expect(_textSendActionFinder(), findsNothing);
        expect(_sendSpinnerFinder(), findsNothing);

        expect(find.text('draft text'), findsNothing);
      },
    );

    testWidgets('voice send has localized tooltip and semantics when locked', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

        final barState = tester.state<ChatInputBarState>(
          find.byType(ChatInputBar),
        );
        barState.setRecordingForTest(true);
        barState.setRecordingLockedForTest(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(_voiceSendActionFinder(), findsOneWidget);
        expect(find.byTooltip('Send voice message'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Send voice message'))
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      'locked voice send supports semantic tap action without crashing',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

          final barState = tester.state<ChatInputBarState>(
            find.byType(ChatInputBar),
          );
          barState.setRecordingForTest(true);
          barState.setRecordingLockedForTest(true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));

          final semanticsFinder = find.bySemanticsLabel('Send voice message');
          expect(semanticsFinder, findsOneWidget);
          expect(
            tester
                .getSemantics(semanticsFinder)
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          await tester.tap(semanticsFinder);
          await tester.pump();

          expect(find.byType(ChatInputBar), findsOneWidget);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('tap voice send invokes sendLockedRecording without crashing', (
      tester,
    ) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final barState = tester.state<ChatInputBarState>(
        find.byType(ChatInputBar),
      );
      barState.setRecordingForTest(true);
      barState.setRecordingLockedForTest(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(_voiceSendActionFinder(), findsOneWidget);
      await tester.tap(find.byTooltip('Send voice message'));
      await tester.pump();

      expect(find.byType(ChatInputBar), findsOneWidget);
    });

    testWidgets('after recording ends draft text send returns', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), 'kept draft');
      await tester.pump();

      final barState = tester.state<ChatInputBarState>(
        find.byType(ChatInputBar),
      );
      barState.setRecordingForTest(true);
      barState.setRecordingLockedForTest(true);
      await tester.pump();

      barState.setRecordingForTest(false);
      barState.setRecordingLockedForTest(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));

      expect(find.text('kept draft'), findsOneWidget);
      expect(_textSendActionFinder(), findsOneWidget);
      expect(_voiceSendActionFinder(), findsNothing);
    });
  });

  group('RecordingController trailing slot', () {
    testWidgets('shows spinner when isSendingVoice', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordingController(
              onVoiceSent:
                  ({required duration, localAudioPath, audioBytes}) async {},
              onRecordingStateChanged: (_) {},
              isSendingVoice: true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsNothing);
    });
  });
}
