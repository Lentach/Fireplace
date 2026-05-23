import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/input/reply_preview_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('encrypted content shows Encrypted message l10n', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<EncryptionProvider>(
          create: (_) => EncryptionProvider(),
          child: Scaffold(
            body: ReplyPreviewBar(
              message: MessageModel(
                id: 1,
                content: '[encrypted]',
                senderId: 2,
                senderUsername: 'bob',
                conversationId: 10,
                createdAt: DateTime.utc(2026, 1, 1),
              ),
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Encrypted message'), findsOneWidget);
    expect(find.text('[encrypted]'), findsNothing);
  });
}
