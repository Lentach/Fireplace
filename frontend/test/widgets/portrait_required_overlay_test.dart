import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/widgets/portrait_required_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows localized rotate message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('pl'),
        home: const PortraitRequiredOverlay(),
      ),
    );
    expect(find.text('Obróć urządzenie'), findsOneWidget);
    expect(find.textContaining('trybie pionowym'), findsOneWidget);
  });
}
