import 'package:fireplace/utils/jumbo_emoji.dart';
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
      1: 40,
      2: 40,
      3: 34,
      4: 26,
      5: 22,
      6: 22,
      50: 22,
    };
    tiers.forEach((count, size) {
      test('$count emoji -> $size', () {
        expect(jumboEmojiFontSizeForCount(count), size);
      });
    });
  });

  group('jumboEmojiFontSize', () {
    test('emoji-only text maps through the tier table', () {
      expect(jumboEmojiFontSize('😀'), 40);
      expect(jumboEmojiFontSize('😀😀😀'), 34);
      expect(jumboEmojiFontSize('😀😀😀😀'), 26);
      expect(jumboEmojiFontSize('😀 😀 😀 😀 😀 😀'), 22);
    });

    test('null for non-emoji-only text', () {
      expect(jumboEmojiFontSize('hi 😀'), isNull);
      expect(jumboEmojiFontSize(''), isNull);
    });
  });
}
