import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/chat_message_bubble.dart';
import 'package:fireplace/widgets/message/message_metadata_row.dart';
import 'package:fireplace/widgets/message/text_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Regression tests for the emoji-only ("emote") bubble layout (P1 + P2):
/// the time + disappearing-timer indicators must stack UNDER the emote and
/// stay aligned to the message side, NOT sit inline in a `Wrap` beside it
/// (the old layout shoved lone emotes toward center and dropped the metadata
/// run on iOS WebKit).
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
}
