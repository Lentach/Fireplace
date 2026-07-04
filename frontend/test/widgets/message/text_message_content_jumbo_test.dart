import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/message_context_menu_bubble_highlight.dart';
import 'package:fireplace/widgets/message/text_message_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MessageModel _msg(String content) => MessageModel(
  id: 1,
  content: content,
  senderId: 1,
  senderUsername: 'alice',
  conversationId: 1,
  createdAt: DateTime(2026, 5, 23),
  deliveryStatus: MessageDeliveryStatus.sent,
  messageType: MessageType.text,
);

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: RpgTheme.themeDataLight,
  home: Scaffold(body: Center(child: child)),
);

Widget _textContent(String content) => _wrap(
  TextMessageContent(
    message: _msg(content),
    isMine: true,
    textColor: Colors.black,
    isDark: false,
    maxWidth: 280,
  ),
);

RichText _richTextOf(WidgetTester tester) => tester.widget<RichText>(
  find.descendant(
    of: find.byType(TextMessageContent),
    matching: find.byType(RichText),
  ),
);

void main() {
  group('TextMessageContent jumbo emoji', () {
    testWidgets('emoji-only message renders as RichText at fontSize 84', (
      tester,
    ) async {
      await tester.pumpWidget(_textContent('😀'));
      final span = _richTextOf(tester).text as TextSpan;
      expect(span.style?.fontSize, 84);
      expect((span.children!.single as TextSpan).text, '😀');
    });

    testWidgets('five emoji render at fontSize 44', (tester) async {
      await tester.pumpWidget(_textContent('😀😀😀😀😀'));
      final span = _richTextOf(tester).text as TextSpan;
      expect(span.style?.fontSize, 44);
      expect((span.children!.single as TextSpan).text, '😀😀😀😀😀');
    });

    testWidgets('plain text keeps the 14px RichText pipeline', (tester) async {
      await tester.pumpWidget(_textContent('hello world'));
      // No jumbo Text widget: mixed/plain content stays on the span pipeline.
      expect(find.text('hello world'), findsNothing);
      final span = _richTextOf(tester).text as TextSpan;
      final child = span.children!.single as TextSpan;
      expect(child.text, 'hello world');
      expect(child.style?.fontSize, 14);
    });

    testWidgets('emoji next to a URL keeps the 14px RichText pipeline', (
      tester,
    ) async {
      await tester.pumpWidget(_textContent('https://x.com 😀'));
      final span = _richTextOf(tester).text as TextSpan;
      final spans = span.children!.cast<TextSpan>();
      expect(spans, isNotEmpty);
      expect(
        spans.every((s) => s.style?.fontSize == 14),
        isTrue,
        reason: 'URL + emoji must not trigger jumbo sizing',
      );
    });
  });

  group('MessageContextMenuBubbleHighlight jumbo emoji', () {
    testWidgets('emoji-only TEXT replica renders body at fontSize 84', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MessageContextMenuBubbleHighlight(
            message: _msg('😀'),
            isMine: true,
            maxWidth: 200,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('😀'));
      expect(text.style?.fontSize, 84);
    });

    testWidgets('plain-text replica keeps body fontSize 15', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageContextMenuBubbleHighlight(
            message: _msg('hello'),
            isMine: true,
            maxWidth: 200,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('hello'));
      expect(text.style?.fontSize, 15);
    });
  });
}
