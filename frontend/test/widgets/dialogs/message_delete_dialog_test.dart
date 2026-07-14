import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/widgets/dialogs/message_delete_dialog.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({required bool isMine, required int messageId}) {
    return MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showMessageDeleteDialog(
              context: ctx,
              isMine: isMine,
              messageId: messageId,
              onDeleteForMe: () {},
              onDeleteForEveryone: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('other user message hides delete for everyone', (tester) async {
    await tester.pumpWidget(wrap(isMine: false, messageId: 42));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsNothing);
  });

  testWidgets('own persisted message shows both options', (tester) async {
    await tester.pumpWidget(wrap(isMine: true, messageId: 42));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsOneWidget);
  });

  testWidgets('own optimistic temp id hides delete for everyone', (tester) async {
    await tester.pumpWidget(wrap(isMine: true, messageId: -1));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for everyone'), findsNothing);
  });
}
