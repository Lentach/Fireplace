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

/// Returns the single [RichText] inside [TextMessageContent].
RichText _richTextOf(WidgetTester tester) => tester.widget<RichText>(
  find.descendant(
    of: find.byType(TextMessageContent),
    matching: find.byType(RichText),
  ),
);

/// Finds the body [Text.rich] widget inside [MessageContextMenuBubbleHighlight].
///
/// The body for mixed/plain messages is a [Text] with [textSpan] set (Text.rich).
/// The metadata-row time widget is a plain [Text] with [data] set and [textSpan]
/// null, so it does not match.
Text _bubbleBodyText(WidgetTester tester) => tester.widget<Text>(
  find.descendant(
    of: find.byType(MessageContextMenuBubbleHighlight),
    matching: find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
  ),
);

void main() {
  group('TextMessageContent jumbo emoji', () {
    testWidgets('emoji-only message renders as RichText at fontSize 82', (
      tester,
    ) async {
      await tester.pumpWidget(_textContent('😀'));
      final span = _richTextOf(tester).text as TextSpan;
      expect(span.style?.fontSize, 82);
      expect((span.children!.single as TextSpan).text, '😀');
    });

    testWidgets('five emoji render at fontSize 44', (tester) async {
      await tester.pumpWidget(_textContent('😀😀😀😀😀'));
      final span = _richTextOf(tester).text as TextSpan;
      expect(span.style?.fontSize, 44);
      expect((span.children!.single as TextSpan).text, '😀😀😀😀😀');
    });

    // Locks the intermediate step-down curve, not just its endpoints (1->82,
    // 5->44). An off-by-one in the count->size map or a swapped tier value
    // would slip past the endpoint-only tests.
    for (final tier in const {2: 78.0, 3: 64.0, 4: 52.0}.entries) {
      testWidgets('${tier.key} emoji render at fontSize ${tier.value.toInt()}', (
        tester,
      ) async {
        final emoji = '😀' * tier.key;
        await tester.pumpWidget(_textContent(emoji));
        final span = _richTextOf(tester).text as TextSpan;
        expect(span.style?.fontSize, tier.value);
        expect((span.children!.single as TextSpan).text, emoji);
      });
    }

    testWidgets('plain text keeps the 14px RichText pipeline', (tester) async {
      await tester.pumpWidget(_textContent('hello world'));
      // No plain Text widget — it's rendered directly as RichText spans.
      expect(find.text('hello world'), findsNothing);
      final span = _richTextOf(tester).text as TextSpan;
      final child = span.children!.single as TextSpan;
      expect(child.text, 'hello world');
      expect(child.style?.fontSize, 14);
    });

    testWidgets('mixed text+emoji: text span 14, emoji span 18, no jumbo', (
      tester,
    ) async {
      await tester.pumpWidget(_textContent('hi 😀'));
      final span = _richTextOf(tester).text as TextSpan;
      final spans = span.children!.cast<TextSpan>();
      expect(spans.length, 2);
      expect(spans[0].text, 'hi ');
      expect(spans[0].style?.fontSize, 14);
      expect(spans[1].text, '😀');
      expect(spans[1].style?.fontSize, 18);
      // None of the spans are jumbo-sized
      for (final s in spans) {
        expect(
          (s.style?.fontSize ?? 0) < 82,
          isTrue,
          reason: 'span "${s.text}" must not have jumbo fontSize',
        );
      }
    });

    testWidgets(
      'URL plus emoji: no jumbo, URL and surrounding text stay 14, emoji is 18',
      (tester) async {
        await tester.pumpWidget(_textContent('https://x.com 😀'));
        final span = _richTextOf(tester).text as TextSpan;
        final spans = span.children!.cast<TextSpan>();
        expect(spans, isNotEmpty);

        // No span triggers jumbo sizing
        for (final s in spans) {
          expect(
            (s.style?.fontSize ?? 0) < 82,
            isTrue,
            reason: 'span "${s.text}" must not have jumbo fontSize',
          );
        }

        // URL span: has a tap recognizer, fontSize 14, underlined
        final urlSpan = spans.firstWhere((s) => s.recognizer != null);
        expect(urlSpan.style?.fontSize, 14);
        expect(urlSpan.style?.decoration, TextDecoration.underline);

        // Emoji span: fontSize 18 (inline emoji enlargement, not jumbo)
        final emojiSpan = spans.firstWhere((s) => s.text == '😀');
        expect(emojiSpan.style?.fontSize, 18);

        // Every other span (e.g. the space ' ') stays at 14
        for (final s in spans.where((s) => s.recognizer == null && s.text != '😀')) {
          expect(s.style?.fontSize, 14);
        }
      },
    );
  });

  group('MessageContextMenuBubbleHighlight jumbo emoji', () {
    testWidgets('emoji-only TEXT replica renders body as plain Text at fontSize 82', (
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
      // Emoji-only body is a plain Text widget (not Text.rich); style is direct.
      final text = tester.widget<Text>(find.text('😀'));
      expect(text.style?.fontSize, 82);
    });

    testWidgets(
      'plain-text replica is Text.rich with single child span at fontSize 15',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MessageContextMenuBubbleHighlight(
              message: _msg('hello'),
              isMine: true,
              maxWidth: 200,
            ),
          ),
        );
        // Mixed/plain body is Text.rich: Text.style is null; sizing is on spans.
        final text = _bubbleBodyText(tester);
        expect(text.style, isNull);
        final rootSpan = text.textSpan as TextSpan;
        final child = rootSpan.children!.single as TextSpan;
        expect(child.text, 'hello');
        expect(child.style?.fontSize, 15);
      },
    );

    testWidgets(
      'mixed-text replica has text span at 15 and emoji span at 18',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MessageContextMenuBubbleHighlight(
              message: _msg('hi 😀'),
              isMine: true,
              maxWidth: 200,
            ),
          ),
        );
        final text = _bubbleBodyText(tester);
        expect(text.style, isNull);
        final rootSpan = text.textSpan as TextSpan;
        final children = rootSpan.children!.cast<TextSpan>();
        expect(children.length, 2);
        expect(children[0].text, 'hi ');
        expect(children[0].style?.fontSize, 15);
        expect(children[1].text, '😀');
        expect(children[1].style?.fontSize, 18);
      },
    );
  });
}
