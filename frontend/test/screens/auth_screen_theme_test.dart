import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/chat_background_preference.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/screens/auth_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/auth_form.dart';
import 'package:fireplace/widgets/chat_background_pattern.dart';

// Owner ruling 2026-07-28 (supersedes the 2026-07-18 always-Cosmic door):
// the front door ALWAYS wears Hot Stone — light theme, plain warm-paper
// backdrop — regardless of the ambient app theme.
void main() {
  testWidgets('auth screen always wears the Hot Stone light theme', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        // Ambient app theme is DARK on purpose: the door must override it.
        theme: RpgTheme.themeDataDarkGray,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ChangeNotifierProvider(
          create: (_) => AuthProvider(),
          child: const AuthScreen(),
        ),
      ),
    );
    await tester.pump();

    // The theme INSIDE the door is the light one, not the ambient dark.
    final formContext = tester.element(find.byType(AuthForm));
    final theme = Theme.of(formContext);
    expect(theme.brightness, Brightness.light);
    expect(
      theme.scaffoldBackgroundColor,
      RpgTheme.themeDataLight.scaffoldBackgroundColor,
    );

    // Backdrop is the plain warm paper — no starfield, no wallpaper leak.
    final pattern = tester.widget<ChatBackgroundPattern>(
      find.byType(ChatBackgroundPattern),
    );
    expect(pattern.layer, ChatBackgroundLayer.plain);
  });
}
