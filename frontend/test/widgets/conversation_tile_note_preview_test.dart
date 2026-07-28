import 'package:fireplace/config/app_config.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/conversation_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

void main() {
  // Own-origin note URL: whole trimmed content is one note link, so the tile
  // preview must show the label, never the raw URL.
  final noteUrl =
      '${AppConfig.baseUrl}/note/0123456789abcdef0123456789abcdef#abcABC012_-';

  testWidgets('tile shows note label instead of raw note URL', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConversationTile(
          conversationId: 10,
          displayName: 'Alice',
          lastMessage: MessageModel(
            id: 1,
            content: noteUrl,
            senderId: 2,
            senderUsername: 'alice',
            conversationId: 10,
            createdAt: DateTime.now(),
          ),
          onTap: () {},
          onDelete: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Anti-Quantum Note', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('/note/', findRichText: true),
      findsNothing,
    );
  });
}
