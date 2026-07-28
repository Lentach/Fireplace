import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Owner ruling 2026-07-28 (bug 4): on mobile the virtual keyboard's action key
// inserts a NEWLINE — sending is the on-screen send button only. Desktop keeps
// TextInputAction.send + onSubmitted (plus the Ctrl/Cmd+Enter shortcuts). The
// platform branch keys off defaultTargetPlatform, which reflects the host OS
// on web too, so a phone PWA counts as mobile.

Future<void> _pump(WidgetTester tester) async {
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
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: const ChatInputBar(),
        ),
      ),
    ),
  );
  await tester.pump();
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  // NOTE: debugDefaultTargetPlatformOverride must be reset INSIDE each test
  // body — the flutter_test binding verifies foundation debug variables
  // before tearDown callbacks run, so a tearDown-only reset still fails with
  // "value of a foundation debug variable was changed by the test".
  // Leak insurance only: if a body throws before its own reset, this stops
  // the override cascading into later tests (that test still fails).
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform: action key is newline and onSubmitted is absent', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      await _pump(tester);

      final field = _field(tester);
      expect(field.textInputAction, TextInputAction.newline);
      expect(field.onSubmitted, isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform: action key still sends', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await _pump(tester);

      final field = _field(tester);
      expect(field.textInputAction, TextInputAction.send);
      expect(field.onSubmitted, isNotNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
