import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/chat_message_bubble.dart';
import 'package:fireplace/widgets/message/message_metadata_row.dart';
import 'package:fireplace/widgets/message/text_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
/// Regression tests for emoji-only ("emote") message rendering:
/// - P1: the time + disappearing-timer indicators stack UNDER the emote,
///   aligned to the message side, not inline in a `Wrap` beside it (which
///   shoved lone emotes toward center).
/// - P2: the bubbleless emote metadata uses an on-chat-surface color so it is
///   legible on a light background (the on-bubble sent color is white).
MessageModel _emote(String content, {required int senderId}) => MessageModel(
  id: 1,
  content: content,
  senderId: senderId,
  senderUsername: 'alice',
  conversationId: 1,
  createdAt: DateTime(2026, 5, 23),
  deliveryStatus: MessageDeliveryStatus.sent,
  messageType: MessageType.text,
);

Future<void> _pumpEmote(
  WidgetTester tester,
  String content, {
  required bool isMine,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: RpgTheme.themeDataLight,
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            ChangeNotifierProvider<MessagingProvider>(
              create: (_) => MessagingProvider(),
            ),
            ChangeNotifierProvider<SettingsProvider>(
              create: (_) => SettingsProvider(),
            ),
          ],
          child: SizedBox(
            width: 390,
            height: 600,
            child: ChatMessageBubble(
              message: _emote(content, senderId: isMine ? 1 : 2),
              isMine: isMine,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _emoteFinder => find.descendant(
  of: find.byType(TextMessageContent),
  matching: find.byType(RichText),
);

void main() {
  group('emoji-only bubble layout', () {
    for (final content in const ['😀', '😀😀', '😀😀😀']) {
      testWidgets('incoming "$content": metadata under emote, left-aligned', (
        tester,
      ) async {
        await _pumpEmote(tester, content, isMine: false);

        expect(find.byType(MessageMetadataRow), findsOneWidget);
        final emote = tester.getRect(_emoteFinder);
        final meta = tester.getRect(find.byType(MessageMetadataRow));

        // Stacked UNDER the emote, not inline beside it.
        expect(
          meta.top,
          greaterThanOrEqualTo(emote.bottom - 1),
          reason: 'metadata must sit below the emote',
        );
        // Incoming stays flush-left: metadata shares the emote's left edge.
        expect(
          (meta.left - emote.left).abs(),
          lessThan(4),
          reason: 'incoming emote + metadata are start-aligned',
        );
        // The old inline layout used a Wrap; the fix must not.
        expect(
          find.descendant(
            of: find.byType(ChatMessageBubble),
            matching: find.byType(Wrap),
          ),
          findsNothing,
          reason: 'emoji-only must stack in a Column, never an inline Wrap',
        );
      });
    }

    testWidgets('outgoing single emote: metadata under emote, right-aligned', (
      tester,
    ) async {
      await _pumpEmote(tester, '😀', isMine: true);

      expect(find.byType(MessageMetadataRow), findsOneWidget);
      final emote = tester.getRect(_emoteFinder);
      final meta = tester.getRect(find.byType(MessageMetadataRow));

      expect(
        meta.top,
        greaterThanOrEqualTo(emote.bottom - 1),
        reason: 'metadata must sit below the emote',
      );
      // Outgoing stays flush-right: metadata shares the emote's right edge.
      expect(
        (meta.right - emote.right).abs(),
        lessThan(4),
        reason: 'outgoing emote + metadata are end-aligned',
      );
    });

    testWidgets('emote is not wrapped in the normal bubble surface', (
      tester,
    ) async {
      // Emoji-only messages render outside the colored bubble surface, so the
      // surface key present on normal text bubbles must be absent.
      await _pumpEmote(tester, '😀', isMine: false);
      expect(find.byKey(const ValueKey('message-bubble-surface-1')), findsNothing);
    });
  });

  group('emote metadata color + reply bubble sizing', () {
    testWidgets('outgoing emote metadata uses on-chat-surface color, not white', (
      tester,
    ) async {
      // The persisted iOS light-theme bug: bubbleless emote metadata used the
      // on-bubble sent color (white), invisible on the light chat background.
      await _pumpEmote(tester, '😀', isMine: true);
      final meta = tester.widget<MessageMetadataRow>(
        find.byType(MessageMetadataRow),
      );
      expect(
        meta.onChatSurface,
        isTrue,
        reason: 'bubbleless emote metadata must render in on-surface mode',
      );
      expect(
        meta.timeColor,
        isNot(Colors.white),
        reason: 'on-surface meta must not use the invisible on-bubble white',
      );
    });

    testWidgets('reply-to-emote bubble hugs its content, not the max width', (
      tester,
    ) async {
      final msg = MessageModel(
        id: 5,
        content: 'wow',
        senderId: 1,
        senderUsername: 'me',
        conversationId: 1,
        createdAt: DateTime(2026, 5, 23),
        deliveryStatus: MessageDeliveryStatus.sent,
        messageType: MessageType.text,
        replyTo: const ReplyToPreview(
          id: 2,
          content: '🖤',
          senderUsername: 'bob',
          messageType: MessageType.text,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: RpgTheme.themeDataLight,
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider<AuthProvider>(
                  create: (_) => AuthProvider(),
                ),
                ChangeNotifierProvider<MessagingProvider>(
                  create: (_) => MessagingProvider(),
                ),
                ChangeNotifierProvider<SettingsProvider>(
                  create: (_) => SettingsProvider(),
                ),
                ChangeNotifierProvider<EncryptionProvider>(
                  create: (_) => EncryptionProvider(),
                ),
              ],
              child: SizedBox(
                width: 390,
                height: 600,
                child: ChatMessageBubble(message: msg, isMine: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // maxBubbleWidth = 390 * 0.85 = 331.5; the old greedy Align forced the
      // surface to 331.5 - 48 (left pad) = 283.5 regardless of content. With a
      // one-emote quote the bubble must shrink-wrap well below that.
      final surface = tester.getSize(
        find.byKey(const ValueKey('message-bubble-surface-5')),
      );
      expect(
        surface.width,
        lessThan(200),
        reason: 'reply bubble must hug narrow content, not fill max width',
      );
    });
  });
}
