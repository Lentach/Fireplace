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
      1: 84,
      2: 84,
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
      expect(jumboEmojiFontSize('😀'), 84);
      expect(jumboEmojiFontSize('😀😀😀'), 64);
      expect(jumboEmojiFontSize('😀😀😀😀'), 52);
      expect(jumboEmojiFontSize('😀 😀 😀 😀 😀 😀'), 44);
    });

    test('null for non-emoji-only text', () {
      expect(jumboEmojiFontSize('hi 😀'), isNull);
      expect(jumboEmojiFontSize(''), isNull);
    });
  });
}
