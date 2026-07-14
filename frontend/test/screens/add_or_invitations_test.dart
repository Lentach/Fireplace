import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/screens/add_or_invitations_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';

void main() {
  testWidgets(
      'pending-open conversation pops the screen with the id (listener, not build)',
      (tester) async {
    final convs = ConversationsProvider();
    final friends = FriendsProvider();
    final conn = ConnectionProvider();
    Object? popped;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: convs),
          ChangeNotifierProvider.value(value: friends),
          ChangeNotifierProvider.value(value: conn),
        ],
        child: MaterialApp(
          theme: RpgTheme.themeDataLight,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(ctx).push<Object?>(
                      MaterialPageRoute<Object?>(
                        builder: (_) => const AddOrInvitationsScreen(),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AddOrInvitationsScreen), findsOneWidget);

    // Socket-style pending-open arrives AFTER the screen mounted. The add-tab's
    // provider listener (not build()) must consume it and pop with the id.
    convs.onOpenConversation({'conversationId': 42});
    await tester.pumpAndSettle();

    expect(popped, 42);
    expect(find.byType(AddOrInvitationsScreen), findsNothing);
  });
}
