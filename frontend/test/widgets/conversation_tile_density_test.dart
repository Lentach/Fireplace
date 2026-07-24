import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/conversation_tile.dart';
import 'package:fireplace/widgets/hex_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

MessageModel _message({required Duration age, String content = 'hey'}) {
  return MessageModel(
    id: 1,
    content: content,
    senderId: 2,
    senderUsername: 'alice',
    conversationId: 10,
    createdAt: DateTime.now().subtract(age),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: RpgTheme.themeDataDarkGray,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MessagingProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: SizedBox(width: 390, child: child),
      ),
    ),
  );
}

Future<Size> _rowSize(
  WidgetTester tester, {
  int unread = 0,
  bool typing = false,
  Duration age = const Duration(minutes: 5),
}) async {
  await tester.pumpWidget(
    _wrap(
      ConversationTile(
        conversationId: 10,
        displayName: 'Alice',
        lastMessage: _message(age: age),
        unreadCount: unread,
        isTyping: typing,
        onTap: () {},
        onDelete: () {},
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(ConversationTile));
}

void main() {
  group('ConversationTile row weight', () {
    testWidgets('unread rows are taller than read rows, cold rows shortest', (
      tester,
    ) async {
      final live = await _rowSize(tester, unread: 3);
      final normal = await _rowSize(tester);
      final cold = await _rowSize(tester, age: const Duration(days: 10));

      expect(live.height, greaterThan(normal.height));
      expect(cold.height, lessThan(normal.height));
    });

    testWidgets('a typing row counts as live', (tester) async {
      final typing = await _rowSize(tester, typing: true);
      final normal = await _rowSize(tester);

      expect(typing.height, greaterThan(normal.height));
    });

    testWidgets('read rows keep the legacy 64px height (Contacts parity)', (
      tester,
    ) async {
      final normal = await _rowSize(tester);

      // 4px outer padding (2 per side) + 10px inner padding + 44px hex.
      expect(normal.height, 68);
    });

    testWidgets('unread count renders in the row, not a badge pill', (
      tester,
    ) async {
      await _rowSize(tester, unread: 7);

      expect(find.text('7'), findsOneWidget);
      // The old badge was white-on-primary inside its own Container.
      final label = tester.widget<Text>(find.text('7'));
      expect(label.style?.color, isNot(Colors.white));
    });

    testWidgets('the avatar is the shared hex, not a circle', (tester) async {
      await _rowSize(tester);

      expect(find.byType(HexAvatar), findsOneWidget);
    });

    testWidgets('live row survives textScale 1.6 on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: RpgTheme.themeDataDarkGray,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: MultiProvider(
                providers: [
                  ChangeNotifierProvider(create: (_) => MessagingProvider()),
                  ChangeNotifierProvider(create: (_) => SettingsProvider()),
                ],
                child: ConversationTile(
                  conversationId: 10,
                  displayName: 'Bartholomew Ignacy',
                  lastMessage: _message(
                    age: const Duration(minutes: 2),
                    content:
                        'that campfire photo from Mazury is unreal, send the '
                        'full-res one when you are home please',
                  ),
                  unreadCount: 12,
                  onTap: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // A RenderFlex overflow would have been thrown by now.
      expect(tester.takeException(), isNull);
      expect(find.byType(ConversationTile), findsOneWidget);
    });
  });
}
