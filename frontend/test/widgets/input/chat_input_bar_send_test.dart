import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:fireplace/widgets/input/composer_keyboard_signals.dart';
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
              create: (_) => SettingsProvider(initialThemePreference: 'light'),
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
  setUp(() => composerKeyboardCollapseGuard.value = false);
  tearDown(() => composerKeyboardCollapseGuard.value = false);

  // Boundary: the empty-text no-op must still precede any send side effect, so it
  // must NOT arm the collapse guard (the guard is armed only on a real send).
  testWidgets('empty send is a no-op and does not arm the collapse guard',
      (tester) async {
    final state = await _pump(tester);
    state.sendForTest();
    await tester.pump();
    expect(composerKeyboardCollapseGuard.value, isFalse);
  });

  // A real send routes through `_send()` (which dispatches to MessagingProvider)
  // and arms the keyboard collapse guard so the viewport keeps the flash guard.
  testWidgets('non-empty send arms the keyboard collapse guard',
      (tester) async {
    final state = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    state.sendForTest();
    await tester.pump();
    expect(composerKeyboardCollapseGuard.value, isTrue);
  });
}
