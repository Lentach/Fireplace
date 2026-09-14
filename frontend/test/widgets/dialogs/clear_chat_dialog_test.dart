import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/dialogs/clear_chat_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `clearChatHistory` is irreversible AND destroys the peer's copy of the whole
/// thread, so the emit must happen only on an explicit confirmation. The gate
/// is what these tests defend — not the wording of the warning.
void main() {
  Widget wrap({required VoidCallback onConfirm}) {
    return MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () =>
                showClearChatDialog(context: ctx, onConfirm: onConfirm),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirming fires the wipe exactly once and closes', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(wrap(onConfirm: () => fired++));
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('clear-chat-confirm')));
    await tester.pumpAndSettle();

    expect(fired, 1);
    expect(find.byKey(const Key('clear-chat-confirm')), findsNothing);
  });

  testWidgets('cancelling never fires the wipe', (tester) async {
    var fired = 0;
    await tester.pumpWidget(wrap(onConfirm: () => fired++));
    await openDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fired, 0);
    expect(find.byKey(const Key('clear-chat-confirm')), findsNothing);
  });

  testWidgets('dismissing by barrier tap never fires the wipe', (tester) async {
    var fired = 0;
    await tester.pumpWidget(wrap(onConfirm: () => fired++));
    await openDialog(tester);

    // A barrier tap is the other way out of a dialog route; it must be as
    // inert as Cancel, never a silent confirm.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(fired, 0);
    expect(find.byKey(const Key('clear-chat-confirm')), findsNothing);
  });

  testWidgets('the warning names the peer and the irreversibility', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(onConfirm: () {}));
    await openDialog(tester);

    // Not pinning the sentence, only the two facts a user must not be able to
    // miss: it hits the other person, and it cannot be undone. The old copy
    // ("Chat history deleted") disclosed neither.
    final warning = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ')
        .toLowerCase();
    expect(warning, contains('other person'));
    expect(warning, contains('cannot be undone'));
  });
}
