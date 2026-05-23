import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/conversation_model.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/utils/pinned_banner_visibility.dart';
import 'package:fireplace/utils/reply_preview_helper.dart';
import 'package:fireplace/widgets/message/pinned_message_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

ConversationModel _conversationWithPinnedPreview({
  required int conversationId,
  required int pinnedMessageId,
  MessageModel? preview,
}) {
  final userA = UserModel(id: 1, username: 'alice', tag: '0001');
  final userB = UserModel(id: 2, username: 'bob', tag: '0002');
  return ConversationModel(
    id: conversationId,
    userOne: userA,
    userTwo: userB,
    createdAt: DateTime.utc(2026, 1, 1),
    pinnedMessageId: pinnedMessageId,
    pinnedMessagePreview: preview ??
        MessageModel(
          id: pinnedMessageId,
          content: 'Pinned preview text',
          senderId: userB.id,
          senderUsername: userB.username,
          conversationId: conversationId,
          createdAt: DateTime.utc(2026, 1, 2),
        ),
  );
}

void main() {
  test('shouldShowPinnedMessageBanner true without local messages list row', () {
    const pinnedMessageId = 999;
    final conv = _conversationWithPinnedPreview(
      conversationId: 10,
      pinnedMessageId: pinnedMessageId,
    );

    expect(shouldShowPinnedMessageBanner(conv), isTrue);
  });

  test('shouldShowPinnedMessageBanner false when preview omitted (delete-for-me)', () {
    final conv = ConversationModel(
      id: 10,
      userOne: UserModel(id: 1, username: 'alice', tag: '0001'),
      userTwo: UserModel(id: 2, username: 'bob', tag: '0002'),
      createdAt: DateTime.utc(2026, 1, 1),
      pinnedMessageId: 999,
      pinnedMessagePreview: null,
    );

    expect(shouldShowPinnedMessageBanner(conv), isFalse);
  });

  testWidgets('pinned banner renders from conversation preview only', (tester) async {
    const conversationId = 10;
    const pinnedMessageId = 999;
    final conv = _conversationWithPinnedPreview(
      conversationId: conversationId,
      pinnedMessageId: pinnedMessageId,
    );

    expect(shouldShowPinnedMessageBanner(conv), isTrue);

    final preview = conv.pinnedMessagePreview!;
    await tester.pumpWidget(
      MaterialApp(
        theme: RpgTheme.themeDataLight,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChangeNotifierProvider(
            create: (_) => EncryptionProvider(),
            child: Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context)!;
                final encryption = context.read<EncryptionProvider>();
                return PinnedMessageBanner(
                  previewText: replyPreviewForMessage(
                    l10n,
                    preview,
                    encryption: encryption,
                  ),
                  senderLabel: preview.senderUsername,
                  onTap: () {},
                  onUnpin: () {},
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PinnedMessageBanner), findsOneWidget);
    expect(find.text('Pinned preview text'), findsOneWidget);
  });
}
