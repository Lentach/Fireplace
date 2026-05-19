import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/main_tab_screen_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MainTabScreenHeader spans parent width', (tester) async {
    const viewportWidth = 360.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: viewportWidth,
            child: MainTabScreenHeader(title: 'Contacts'),
          ),
        ),
      ),
    );

    await tester.pump();

    final headerFinder = find.byType(MainTabScreenHeader);
    expect(headerFinder, findsOneWidget);
    expect(tester.getSize(headerFinder).width, viewportWidth);
  });
}
