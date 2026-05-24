import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:fireplace/widgets/input/recording_controller.dart';
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
      'userOne': {
        'id': userA.id,
        'username': userA.username,
        'tag': userA.tag,
      },
      'userTwo': {
        'id': userB.id,
        'username': userB.username,
        'tag': userB.tag,
      },
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'unreadCount': 0,
    },
  ]);
  provider.openConversation(conversationId);
  return provider;
}

MessagingProvider _messagingLinkedTo(ConversationsProvider convs) {
  final messaging = MessagingProvider();
  messaging.setConversationsProvider(convs);
  messaging.setCurrentUserId(1);
  messaging.onConnect(false);
  messaging.setIncomingMessageSoundEnabledForTest(false);
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

Finder _sendOpacityFinder() {
  return find.descendant(
    of: find.ancestor(
      of: find.byType(RecordingController),
      matching: find.byType(Stack),
    ),
    matching: find.byType(AnimatedOpacity),
  );
}

Finder _sendIgnorePointerFinder() {
  return find.descendant(
    of: find.ancestor(
      of: find.byType(RecordingController),
      matching: find.byType(Stack),
    ),
    matching: find.byType(IgnorePointer),
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

    testWidgets('empty field shows mic and hides send overlay', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.byType(RecordingController), findsOneWidget);

      final opacity = tester.widget<AnimatedOpacity>(_sendOpacityFinder());
      expect(opacity.opacity, 0);

      final ignorePointer =
          tester.widget<IgnorePointer>(_sendIgnorePointerFinder());
      expect(ignorePointer.ignoring, isTrue);
    });

    testWidgets('composable text shows send overlay', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));

      final opacity = tester.widget<AnimatedOpacity>(_sendOpacityFinder());
      expect(opacity.opacity, 1);

      final ignorePointer =
          tester.widget<IgnorePointer>(_sendIgnorePointerFinder());
      expect(ignorePointer.ignoring, isFalse);
    });

    testWidgets('whitespace-only field keeps send hidden', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final opacity = tester.widget<AnimatedOpacity>(_sendOpacityFinder());
      expect(opacity.opacity, 0);
    });

    testWidgets('tap send calls sendMessage and clears field', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(messaging.messages, isEmpty);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(messaging.messages.length, 1);
      expect(messaging.messages.first.content, 'hello');
      expect(find.text('hello'), findsNothing);
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

    testWidgets('Ctrl+Enter sends message via CallbackShortcuts',
        (tester) async {
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

    testWidgets('after send focus is retained or restored post-frame',
        (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final textField = find.byType(TextField);
      await tester.tap(textField);
      await tester.pump();
      await tester.enterText(textField, 'hi');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump();

      final focusNode = tester.widget<TextField>(textField).focusNode;
      expect(focusNode?.hasFocus, isTrue);
    });

    testWidgets('RecordingController stays mounted while typing', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      expect(find.byType(RecordingController), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();

      expect(find.byType(RecordingController), findsOneWidget);
    });

    testWidgets('send overlay hidden while recording bar is visible',
        (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final barState =
          tester.state<ChatInputBarState>(find.byType(ChatInputBar));
      barState.setRecordingForTest(true);
      await tester.pump();

      final opacity = tester.widget<AnimatedOpacity>(_sendOpacityFinder());
      expect(opacity.opacity, 0);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('sending voice shows spinner and hides send overlay',
        (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      final barState =
          tester.state<ChatInputBarState>(find.byType(ChatInputBar));
      barState.setSendingVoiceForTest(true);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsNothing);

      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();

      final opacity = tester.widget<AnimatedOpacity>(_sendOpacityFinder());
      expect(opacity.opacity, 0);
    });

    testWidgets('send has localized tooltip when visible', (tester) async {
      await _pumpChatInputBar(tester, convs: convs, messaging: messaging);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));

      expect(find.byTooltip('Send'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Send message' &&
              widget.properties.button == true,
        ),
        findsOneWidget,
      );
    });
  });

  group('RecordingController trailing slot', () {
    testWidgets('shows spinner when isSendingVoice', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordingController(
              onVoiceSent: ({required duration, localAudioPath, audioBytes}) async {},
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
