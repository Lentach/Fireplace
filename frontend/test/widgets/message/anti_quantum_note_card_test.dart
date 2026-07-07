import 'package:fireplace/config/app_config.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/anti_quantum_note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The card's internal parse uses the default AppConfig.baseUrl, so URLs must
  // be built from it for detection/expiry parsing to fire in the test VM.
  const hex = '0123456789abcdef0123456789abcdef';
  const key = 'abcABC012_-';
  final countdownKey = const Key('anti-quantum-note-countdown');

  String noteUrl({int? expiryMs}) {
    final tail = expiryMs == null ? '' : '&e=$expiryMs';
    return '${AppConfig.baseUrl}/note/$hex#$key$tail';
  }

  Widget wrap(String url) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: RpgTheme.themeDataLight,
        home: Scaffold(
          body: Center(
            child: AntiQuantumNoteCard(
              noteUrl: url,
              isMine: true,
              textColor: Colors.black,
              isDark: false,
              maxWidth: 280,
            ),
          ),
        ),
      );

  testWidgets(
    'future expiry shows the live self-destruct countdown + normal subtitle',
    (tester) async {
      final future =
          DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch;
      await tester.pumpWidget(wrap(noteUrl(expiryMs: future)));

      expect(find.byKey(countdownKey), findsOneWidget);
      expect(find.textContaining('Self-destructs in'), findsOneWidget);
      expect(find.text('One-time read · Tap to open'), findsOneWidget);
      expect(find.text('This note has self-destructed'), findsNothing);

      // The card arms a real Timer for future expiry; unmount to dispose and
      // cancel it so no pending-timer assertion fires at teardown.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'past expiry shows the destroyed state and no countdown',
    (tester) async {
      final past =
          DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      await tester.pumpWidget(wrap(noteUrl(expiryMs: past)));

      expect(find.byKey(countdownKey), findsNothing);
      expect(find.text('This note has self-destructed'), findsOneWidget);
      expect(find.text('One-time read · Tap to open'), findsNothing);
    },
  );

  testWidgets(
    'link without an e= param shows no countdown and the normal subtitle',
    (tester) async {
      await tester.pumpWidget(wrap(noteUrl()));

      expect(find.byKey(countdownKey), findsNothing);
      expect(find.text('One-time read · Tap to open'), findsOneWidget);
      expect(find.text('This note has self-destructed'), findsNothing);
    },
  );
}
