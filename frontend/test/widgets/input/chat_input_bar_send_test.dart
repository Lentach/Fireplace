import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/emoji/fireplace_emoji_picker.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:fireplace/widgets/input/composer_keyboard_signals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _providerScope({required Widget child}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ConversationsProvider()),
    ChangeNotifierProvider(create: (_) => MessagingProvider()),
    ChangeNotifierProvider(
      create: (_) => SettingsProvider(initialThemePreference: 'light'),
    ),
  ],
  child: child,
);

Future<ChatInputBarState> _pump(WidgetTester tester) async {
  final key = GlobalKey<ChatInputBarState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: _providerScope(child: ChatInputBar(key: key)),
      ),
    ),
  );
  await tester.pump();
  return key.currentState!;
}

Future<void> _openEmojiPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('composer-emoji-toggle')));
  await tester.pumpAndSettle();
  expect(find.byType(FireplaceEmojiPicker), findsOneWidget);
}

void main() {
  setUp(() => composerKeyboardCollapseGuard.value = false);
  tearDown(() => composerKeyboardCollapseGuard.value = false);

  // Boundary: the empty-text no-op must still precede any send side effect, so it
  // must NOT arm the collapse guard (the guard is armed only on a real send).
  testWidgets('empty send is a no-op and does not arm the collapse guard', (
    tester,
  ) async {
    final state = await _pump(tester);
    state.sendForTest();
    await tester.pump();
    expect(composerKeyboardCollapseGuard.value, isFalse);
  });

  // A real send routes through `_send()` (which dispatches to MessagingProvider)
  // and arms the keyboard collapse guard so the viewport keeps the flash guard.
  testWidgets('non-empty send arms the keyboard collapse guard', (
    tester,
  ) async {
    final state = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    state.sendForTest();
    await tester.pump();
    expect(composerKeyboardCollapseGuard.value, isTrue);
  });

  // Regression: the composer emoji picker must mutate the actual draft field,
  // not just render a detached picker.
  testWidgets('emoji picker opens and inserts a suggested emoji', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Fire ');

    await tester.tap(find.byKey(const ValueKey('composer-emoji-toggle')));
    await tester.pumpAndSettle();

    final suggestedFire = find.byKey(const ValueKey('emoji-picker-option-🔥'));
    expect(suggestedFire, findsOneWidget);

    await tester.tap(suggestedFire);
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Fire 🔥'), findsOneWidget);
  });

  // Telegram parity: focusing the text field swaps the emoji panel for the
  // keyboard — they must never be stacked at the same time.
  testWidgets('composer focus gain closes the emoji panel', (tester) async {
    await _pump(tester);
    await _openEmojiPanel(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byType(FireplaceEmojiPicker), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
  });

  // System back with the panel open must be consumed by the panel
  // (Telegram/Signal parity); only the next back leaves the chat route.
  testWidgets('system back closes the emoji panel before popping the route', (
    tester,
  ) async {
    final key = GlobalKey<ChatInputBarState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: Center(child: Text('conversations-root'))),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: _providerScope(child: ChatInputBar(key: key)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openEmojiPanel(tester);

    // First back: consumed by the panel — the chat route must survive.
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(FireplaceEmojiPicker), findsNothing);
    expect(find.byType(ChatInputBar), findsOneWidget);

    // Second back: nothing left to close, the route pops normally.
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(ChatInputBar), findsNothing);
    expect(find.text('conversations-root'), findsOneWidget);
  });

  // Sending from the emoji panel keeps the panel up and the keyboard down:
  // no refocus may sneak in (a refocus would also close the panel via the
  // focus-gain listener).
  testWidgets('send with the emoji panel open keeps it open and unfocused', (
    tester,
  ) async {
    final state = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'from the panel');
    await _openEmojiPanel(tester);

    state.sendForTest();
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(find.byType(FireplaceEmojiPicker), findsOneWidget);
    expect(field.focusNode!.hasFocus, isFalse);
    // Draft consumed proves the send actually ran (not an early no-op return).
    expect(field.controller!.text, isEmpty);
  });

  // Recording replaces the composer row; a stacked emoji panel must drop
  // with it (mic tap dismisses the panel, Telegram parity).
  testWidgets('starting voice recording closes the emoji panel', (
    tester,
  ) async {
    final state = await _pump(tester);
    await _openEmojiPanel(tester);

    state.setRecordingForTest(true);
    await tester.pump();

    expect(find.byType(FireplaceEmojiPicker), findsNothing);
  });
}
