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

  Widget wrap(
    String url, {
    Future<bool> Function(String token)? aliveProbe,
  }) =>
      MaterialApp(
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
              aliveProbe: aliveProbe,
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
  group('burned-after-read state', () {
    final pillKey = const Key('anti-quantum-note-burned-pill');
    final cardKey = const Key('anti-quantum-note-card');

    testWidgets(
      'note gone before its clock ran out collapses to the burned pill',
      (tester) async {
        final future = DateTime.now()
            .add(const Duration(hours: 2))
            .millisecondsSinceEpoch;
        final probed = <String>[];
        await tester.pumpWidget(wrap(
          noteUrl(expiryMs: future),
          aliveProbe: (token) async {
            probed.add(token);
            return false;
          },
        ));
        await tester.pump();

        expect(probed, [hex]);
        expect(find.byKey(pillKey), findsOneWidget);
        expect(find.byKey(cardKey), findsNothing);
        expect(find.textContaining('Note destroyed'), findsOneWidget);
        expect(find.byKey(countdownKey), findsNothing);
        expect(find.textContaining('it was read'), findsOneWidget);
      },
    );

    testWidgets(
      'alive note keeps the normal card and re-probes on the interval',
      (tester) async {
        final future = DateTime.now()
            .add(const Duration(hours: 2))
            .millisecondsSinceEpoch;
        var probes = 0;
        await tester.pumpWidget(wrap(
          noteUrl(expiryMs: future),
          aliveProbe: (_) async {
            probes++;
            return true;
          },
        ));
        await tester.pump();
        expect(probes, 1);
        expect(find.byKey(cardKey), findsOneWidget);
        expect(find.byKey(pillKey), findsNothing);

        await tester.pump(kNoteAliveProbeInterval);
        await tester.pump();
        expect(probes, 2);
        expect(find.byKey(cardKey), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'probe failure fails open: the card stays alive',
      (tester) async {
        final future = DateTime.now()
            .add(const Duration(hours: 2))
            .millisecondsSinceEpoch;
        await tester.pumpWidget(wrap(
          noteUrl(expiryMs: future),
          aliveProbe: (_) async => throw Exception('offline'),
        ));
        await tester.pump();

        expect(find.byKey(cardKey), findsOneWidget);
        expect(find.byKey(pillKey), findsNothing);
        expect(find.byKey(countdownKey), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'legacy link without e= never probes: gone cannot claim "read"',
      (tester) async {
        var probes = 0;
        await tester.pumpWidget(wrap(
          noteUrl(),
          aliveProbe: (_) async {
            probes++;
            return false;
          },
        ));
        await tester.pump();

        expect(probes, 0);
        expect(find.byKey(cardKey), findsOneWidget);
        expect(find.byKey(pillKey), findsNothing);
      },
    );

    testWidgets(
      'clock-expired card never probes: expiry keeps the destroyed state',
      (tester) async {
        final past = DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch;
        var probes = 0;
        await tester.pumpWidget(wrap(
          noteUrl(expiryMs: past),
          aliveProbe: (_) async {
            probes++;
            return false;
          },
        ));
        await tester.pump();

        expect(probes, 0);
        expect(find.byKey(pillKey), findsNothing);
        expect(find.text('This note has self-destructed'), findsOneWidget);
      },
    );
  });
}
