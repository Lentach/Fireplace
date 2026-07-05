import 'package:fireplace/utils/jumbo_emoji.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('emojiOnlyCount', () {
    const positives = <String, int>{
      '😀': 1, // plain pictograph
      '❤️': 1, // VS16 presentation
      '❤': 1, // bare heart, no VS16
      '👍🏽': 1, // skin-tone modifier
      '👨‍👩‍👧‍👦': 1, // ZWJ family is one grapheme
      '🇵🇱': 1, // flag = regional-indicator pair
      '1️⃣': 1, // keycap
      '😀 😀': 2, // whitespace between emoji allowed
      '😀😀😀😀😀😀': 6,
    };
    positives.forEach((input, expected) {
      test("counts '$input' as $expected", () {
        expect(emojiOnlyCount(input), expected);
      });
    });

    const negatives = <String>[
      'yy',
      '123',
      '#',
      'hi 😀',
      ':)',
      '',
      '   ',
      '[Decryption failed]',
      'https://x.com 😀',
    ];
    for (final input in negatives) {
      test("null for non-emoji-only '$input'", () {
        expect(emojiOnlyCount(input), isNull);
      });
    }
  });

  group('jumboEmojiFontSizeForCount', () {
    const tiers = <int, double>{
      1: 82,
      2: 78,
      3: 64,
      4: 52,
      5: 44,
      6: 44,
      50: 44,
    };
    tiers.forEach((count, size) {
      test('$count emoji -> $size', () {
        expect(jumboEmojiFontSizeForCount(count), size);
      });
    });
  });

  group('jumboEmojiFontSize', () {
    test('emoji-only text maps through the tier table', () {
      expect(jumboEmojiFontSize('😀'), 82);
      expect(jumboEmojiFontSize('😀😀'), 78);
      expect(jumboEmojiFontSize('😀😀😀'), 64);
      expect(jumboEmojiFontSize('😀😀😀😀'), 52);
      expect(jumboEmojiFontSize('😀 😀 😀 😀 😀 😀'), 44);
    });

    test('null for non-emoji-only text', () {
      expect(jumboEmojiFontSize('hi 😀'), isNull);
      expect(jumboEmojiFontSize(''), isNull);
    });
  });

  group('isEmojiGrapheme', () {
    const positives = <String>[
      '😀', // plain pictograph
      '❤️', // VS16 presentation
      '👍🏽', // skin-tone modifier
      '👨‍👩‍👧‍👦', // ZWJ family sequence
      '🇵🇱', // flag (regional-indicator pair)
      '1️⃣', // keycap (digit + VS16 + U+20E3)
    ];
    for (final g in positives) {
      test("'$g' is an emoji grapheme", () {
        expect(isEmojiGrapheme(g), isTrue);
      });
    }

    const negatives = <String>[
      'a', // letter
      '1', // bare digit (no VS16/enclosing keycap)
      '#', // hash (excluded by the regex)
      ' ', // space
    ];
    for (final g in negatives) {
      test("'$g' is not an emoji grapheme", () {
        expect(isEmojiGrapheme(g), isFalse);
      });
    }
  });

  group('buildInlineEmojiSpans', () {
    const baseStyle = TextStyle(fontSize: 14);

    test('pure text produces a single span at textStyle size', () {
      final spans = buildInlineEmojiSpans('hello', textStyle: baseStyle);
      expect(spans.length, 1);
      final span = spans.single as TextSpan;
      expect(span.text, 'hello');
      expect(span.style?.fontSize, 14);
    });

    test("'hi 😀' yields text run at 14 then emoji run at kInlineEmojiFontSize", () {
      final spans = buildInlineEmojiSpans('hi 😀', textStyle: baseStyle);
      expect(spans.length, 2);
      final textRun = spans[0] as TextSpan;
      final emojiRun = spans[1] as TextSpan;
      expect(textRun.text, 'hi ');
      expect(textRun.style?.fontSize, 14);
      expect(emojiRun.text, '😀');
      expect(emojiRun.style?.fontSize, kInlineEmojiFontSize); // 18
    });

    test('consecutive emoji coalesce into one span, not two', () {
      // 'ab😀😀cd' -> ['ab' @14, '😀😀' @18, 'cd' @14]
      final spans = buildInlineEmojiSpans('ab😀😀cd', textStyle: baseStyle);
      expect(spans.length, 3);
      final emojiSpan = spans[1] as TextSpan;
      expect(emojiSpan.text, '😀😀');
      expect(emojiSpan.style?.fontSize, kInlineEmojiFontSize);
      // Surrounding text spans stay at base size
      expect((spans[0] as TextSpan).style?.fontSize, 14);
      expect((spans[2] as TextSpan).style?.fontSize, 14);
    });

    test('custom emojiFontSize overrides the 18px default', () {
      const customSize = 24.0;
      final spans = buildInlineEmojiSpans(
        'x😀',
        textStyle: baseStyle,
        emojiFontSize: customSize,
      );
      expect(spans.length, 2);
      final emojiSpan = spans.last as TextSpan;
      expect(emojiSpan.style?.fontSize, customSize);
      // Non-emoji span is unaffected
      expect((spans.first as TextSpan).style?.fontSize, 14);
    });
  });
}
