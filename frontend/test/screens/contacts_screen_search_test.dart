import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/screens/contacts_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// AuthProvider fake: only [currentUser] matters to the Contacts tab.
class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider(this._user);

  final UserModel? _user;

  @override
  UserModel? get currentUser => _user;
}

Widget _host({required List<String> friendNames}) {
  final friends = FriendsProvider()
    ..onFriendsList([
      for (var i = 0; i < friendNames.length; i++)
        {'id': 100 + i, 'username': friendNames[i], 'tag': '0001'},
    ]);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _FakeAuthProvider(
          UserModel(id: 1, username: 'Marta', tag: '0007'),
        ),
      ),
      ChangeNotifierProvider.value(value: friends),
      ChangeNotifierProvider(create: (_) => ConversationsProvider()),
    ],
    child: MaterialApp(
      theme: RpgTheme.themeDataDarkGray,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
        child: const ContactsScreen(),
      ),
    ),
  );
}

void main() {
  const names = ['ada', 'borys', 'borys24', 'celina'];

  testWidgets('search filters the network view', (tester) async {
    await tester.pumpWidget(_host(friendNames: names));
    await tester.pumpAndSettle();

    for (final name in names) {
      expect(find.text(name), findsOneWidget);
    }

    await tester.enterText(find.byType(TextField), 'bo');
    await tester.pumpAndSettle();

    expect(find.text('borys'), findsOneWidget);
    expect(find.text('borys24'), findsOneWidget);
    expect(find.text('ada'), findsNothing);
    expect(find.text('celina'), findsNothing);
  });

  testWidgets('the same query filters the classic list', (tester) async {
    await tester.pumpWidget(_host(friendNames: names));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'celi');
    await tester.pumpAndSettle();

    // Toggle to the classic list; the query carries over.
    await tester.tap(find.byIcon(Icons.format_list_bulleted));
    await tester.pumpAndSettle();

    expect(find.text('celina'), findsOneWidget);
    expect(find.text('ada'), findsNothing);
    expect(find.text('borys'), findsNothing);
  });

  testWidgets('clear button restores the full set', (tester) async {
    await tester.pumpWidget(_host(friendNames: names));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching contacts'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    for (final name in names) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('no search bar without contacts', (tester) async {
    await tester.pumpWidget(_host(friendNames: const []));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('No contacts yet'), findsOneWidget);
  });
}
