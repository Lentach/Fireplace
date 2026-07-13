import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/screens/user_card_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _wrap(UserCardVisualData data) {
  return MaterialApp(
    theme: RpgTheme.themeDataLight,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider(
      create: (_) => FriendsProvider(),
      child: UserCardScreen(data: data, onMessage: () {}),
    ),
  );
}

void main() {
  const contact = UserCardVisualData(
    userId: 2,
    username: 'alice',
    tag: '0042',
    isSelf: false,
    hasConversation: false,
  );

  testWidgets('requires confirmation before removing or blocking a contact',
      (tester) async {
    await tester.pumpWidget(_wrap(contact));

    await tester.tap(find.text('Remove contact'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Friend?'), findsOneWidget);
    expect(find.text('Remove alice from your contacts? This will delete all conversation history.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Friend?'), findsNothing);

    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Block alice#0042?'), findsOneWidget);
    expect(find.text('You will no longer be able to message this contact.'), findsOneWidget);
  });

  testWidgets('requires confirmation before deleting a profile photo',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const UserCardVisualData(
          userId: 1,
          username: 'ember',
          tag: '7004',
          isSelf: true,
          hasConversation: false,
          photos: [
            UserCardPhoto(
              id: 7,
              url: 'https://example.test/photo.jpg',
              semanticLabel: 'ember#7004',
            ),
          ],
        ),
      ),
    );

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete viewed photo'));
    await tester.pumpAndSettle();

    expect(find.text('Delete photo?'), findsOneWidget);
    expect(find.text('This permanently deletes this profile photo.'), findsOneWidget);
  });
}
