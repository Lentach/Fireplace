import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/widgets/chat_action_tiles.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );

Future<void> _openSheet(
  WidgetTester tester, {
  int? initialSeconds,
  int activeConversationId = 1,
}) async {
  final convs = ConversationsProvider()..openConversation(activeConversationId);
  await tester.pumpWidget(
    ChangeNotifierProvider<ConversationsProvider>.value(
      value: convs,
      child: _wrap(
        Builder(
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
  );
  await tester.tap(find.text('Open timer'));
  await tester.pumpAndSettle();
}

void main() {
  group('DisappearingTimerSheet', () {
    testWidgets('shows four Cupertino pickers and live summary', (tester) async {
      await _openSheet(tester, initialSeconds: 300);

      expect(find.byType(CupertinoPicker), findsNWidgets(4));
      expect(find.text('5 minutes'), findsOneWidget);
      expect(find.text('Disappearing messages'), findsOneWidget);
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

    testWidgets('apply valid duration closes sheet', (tester) async {
      await _openSheet(tester, initialSeconds: 300);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.byType(DisappearingTimerSheet), findsNothing);
    });

    testWidgets('out-of-range selection shows validation error', (tester) async {
      await _openSheet(tester, initialSeconds: 3);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('between 5 seconds and 30 days'),
        findsOneWidget,
      );
      expect(find.byType(DisappearingTimerSheet), findsOneWidget);
    });
  });
}
