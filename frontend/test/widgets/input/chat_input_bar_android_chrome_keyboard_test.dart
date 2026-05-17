import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/utils/android_chrome_web.dart';
import 'package:fireplace/widgets/input/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _layoutSize = Size(400, 800);
const _phantomMqInset = 700.0;

Finder _bottomSpacerWithHeight(double height) => find.byWidgetPredicate(
      (widget) {
        if (widget is! Container) return false;
        final constraints = widget.constraints;
        return constraints != null &&
            constraints.maxHeight == height &&
            constraints.minHeight == height;
      },
    );

Widget _harness({
  required Widget child,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: RpgTheme.themeDataLight,
    home: MediaQuery(
      data: const MediaQueryData(size: _layoutSize).copyWith(
        viewInsets: viewInsets,
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
      ),
      child: Scaffold(
        // Match ChatDetailScreen on Android Chrome Web (manual composer lift).
        resizeToAvoidBottomInset: false,
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ConversationsProvider()),
            ChangeNotifierProvider(create: (_) => MessagingProvider()),
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(initialThemePreference: 'light'),
            ),
          ],
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('ChatInputBar Android Chrome Web keyboard lift', () {
    setUp(() {
      debugForceAndroidChromeWebKeyboardPath = true;
    });

    tearDown(() {
      debugForceAndroidChromeWebKeyboardPath = null;
      debugVisualViewportKeyboardInset = null;
    });

    testWidgets('adds bottom spacer from visual viewport when MQ inset is phantom',
        (tester) async {
      debugVisualViewportKeyboardInset = 320;

      await tester.pumpWidget(
        _harness(
          viewInsets: const EdgeInsets.only(bottom: _phantomMqInset),
          child: const ChatInputBar(),
        ),
      );

      expect(_bottomSpacerWithHeight(320), findsOneWidget);
      expect(_bottomSpacerWithHeight(700), findsNothing);
    });

    testWidgets('caps bottom spacer when visual viewport lags at zero',
        (tester) async {
      debugVisualViewportKeyboardInset = 0;

      await tester.pumpWidget(
        _harness(
          viewInsets: const EdgeInsets.only(bottom: _phantomMqInset),
          child: const ChatInputBar(),
        ),
      );

      expect(_bottomSpacerWithHeight(_layoutSize.height * 0.45), findsOneWidget);
      expect(_bottomSpacerWithHeight(_phantomMqInset), findsNothing);
    });

    testWidgets('does not lift composer when not on Android Chrome Web path',
        (tester) async {
      debugForceAndroidChromeWebKeyboardPath = false;
      debugVisualViewportKeyboardInset = 320;

      await tester.pumpWidget(
        _harness(
          viewInsets: const EdgeInsets.only(bottom: _phantomMqInset),
          child: const ChatInputBar(),
        ),
      );

      expect(_bottomSpacerWithHeight(320), findsNothing);
      expect(_bottomSpacerWithHeight(_phantomMqInset), findsNothing);
    });
  });
}
