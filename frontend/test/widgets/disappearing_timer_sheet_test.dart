import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/disappearing_timer_sheet.dart';
import 'package:fireplace/widgets/hearth_fade_arc.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<ConversationsProvider> _openSheet(
  WidgetTester tester, {
  int? initialSeconds,
  int activeConversationId = 1,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  void Function(String event, dynamic data)? onEmit,
}) async {
  final convs = ConversationsProvider()..openConversation(activeConversationId);
  if (onEmit != null) {
    convs.setEmitCallback(onEmit);
  }
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: theme ?? RpgTheme.themeDataLight,
      home: Scaffold(
        body: ChangeNotifierProvider<ConversationsProvider>.value(
          value: convs,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                final provider = context.read<ConversationsProvider>();
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) =>
                      ChangeNotifierProvider<ConversationsProvider>.value(
                    value: provider,
                    child: DisappearingTimerSheet(
                      initialSeconds: initialSeconds,
                    ),
                  ),
                );
              },
              child: const Text('Open timer'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open timer'));
  await tester.pumpAndSettle();
  return convs;
}

Future<void> _tapSheetButton(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('DisappearingTimerSheet', () {
    testWidgets('shows Hearth Fade hero, explainer, and pickers', (tester) async {
      await _openSheet(tester, initialSeconds: 300);

      expect(find.byType(HearthFadeArcHero), findsOneWidget);
      expect(find.textContaining('after they are read'), findsOneWidget);
      expect(find.byType(CupertinoPicker), findsNWidgets(4));
      expect(find.text('5 minutes'), findsOneWidget);
      expect(find.text('Set timer'), findsOneWidget);
      expect(find.text('Turn off'), findsOneWidget);
    });

    testWidgets('null timer shows all zeros and Off summary', (tester) async {
      await _openSheet(tester, initialSeconds: null);

      expect(find.text('Off'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(4));
    });

    testWidgets('loads 1 day from initialSeconds', (tester) async {
      await _openSheet(tester, initialSeconds: 86400);

      expect(find.text('1 day'), findsOneWidget);
    });

    testWidgets('shows composite summary for multi-part duration', (tester) async {
      const twoDaysThreeMinutes = 2 * 86400 + 3 * 60;
      await _openSheet(tester, initialSeconds: twoDaysThreeMinutes);

      expect(find.text('2 days 3 minutes'), findsOneWidget);
    });

    testWidgets('set timer applies valid duration and closes sheet', (tester) async {
      await _openSheet(tester, initialSeconds: 300);

      await _tapSheetButton(tester, 'Set timer');

      expect(find.byType(DisappearingTimerSheet), findsNothing);
    });

    testWidgets('turn off emits null seconds', (tester) async {
      Map<String, dynamic>? emitted;
      await _openSheet(
        tester,
        initialSeconds: 86400,
        onEmit: (event, data) {
          if (event == 'setDisappearingTimer') {
            emitted = data as Map<String, dynamic>;
          }
        },
      );

      await _tapSheetButton(tester, 'Turn off');

      expect(emitted, isNotNull);
      expect(emitted!['conversationId'], 1);
      expect(emitted!['seconds'], isNull);
    });

    testWidgets('set timer keeps selected seconds', (tester) async {
      Map<String, dynamic>? emitted;
      await _openSheet(
        tester,
        initialSeconds: 300,
        onEmit: (event, data) {
          if (event == 'setDisappearingTimer') {
            emitted = data as Map<String, dynamic>;
          }
        },
      );

      await _tapSheetButton(tester, 'Set timer');

      expect(emitted!['seconds'], 300);
    });

    testWidgets('30 days exactly is valid and applies', (tester) async {
      Map<String, dynamic>? emitted;
      await _openSheet(
        tester,
        initialSeconds: 2592000,
        onEmit: (event, data) {
          if (event == 'setDisappearingTimer') {
            emitted = data as Map<String, dynamic>;
          }
        },
      );

      expect(find.text('30 days'), findsOneWidget);

      await _tapSheetButton(tester, 'Set timer');

      expect(emitted!['seconds'], 2592000);
      expect(find.byType(DisappearingTimerSheet), findsNothing);
    });

    testWidgets('out-of-range selection shows validation error', (tester) async {
      await _openSheet(tester, initialSeconds: 3);

      await _tapSheetButton(tester, 'Set timer');

      expect(
        find.textContaining('between 5 seconds and 30 days'),
        findsOneWidget,
      );
      expect(find.byType(DisappearingTimerSheet), findsOneWidget);
    });

    testWidgets('picker columns expose semantics labels', (tester) async {
      await _openSheet(tester, initialSeconds: 60);

      final pickers = find.byType(CupertinoPicker);
      expect(pickers, findsNWidgets(4));
      final labels = ['Days', 'Hours', 'Minutes', 'Seconds'];
      for (var i = 0; i < labels.length; i++) {
        expect(
          find.ancestor(
            of: pickers.at(i),
            matching: find.bySemanticsLabel(labels[i]),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('renders on dark theme', (tester) async {
      await _openSheet(
        tester,
        initialSeconds: 86400,
        theme: RpgTheme.themeDataDarkGray,
      );

      expect(find.byType(DisappearingTimerSheet), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
    });

    testWidgets('renders on teal theme with themed surface', (tester) async {
      await _openSheet(
        tester,
        initialSeconds: 86400,
        theme: RpgTheme.themeDataTealStone,
      );

      expect(find.byType(DisappearingTimerSheet), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);

      final sheet = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DisappearingTimerSheet),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (sheet.decoration! as BoxDecoration).color,
        RpgTheme.themeDataTealStone.colorScheme.surface,
      );
    });

    testWidgets('renders on blue theme with themed surface', (tester) async {
      await _openSheet(
        tester,
        initialSeconds: 300,
        theme: RpgTheme.themeDataBlue,
      );

      expect(find.byType(DisappearingTimerSheet), findsOneWidget);
      expect(find.text('5 minutes'), findsOneWidget);

      final sheet = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DisappearingTimerSheet),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (sheet.decoration! as BoxDecoration).color,
        RpgTheme.themeDataBlue.colorScheme.surface,
      );
    });

    testWidgets('Polish plural summary for 2 days', (tester) async {
      await _openSheet(
        tester,
        initialSeconds: 2 * 86400,
        locale: const Locale('pl'),
      );

      expect(find.textContaining('2 dni'), findsOneWidget);
    });
  });
}
