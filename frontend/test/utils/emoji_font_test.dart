import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/jumbo_emoji.dart';
import 'package:fireplace/widgets/emoji/fireplace_emoji_picker.dart';

void main() {
  // Red heart MUST be U+2764 U+FE0F. A bare U+2764 renders in text
  // presentation (monochrome outline → looks white on dark); U+1F90D is a
  // DIFFERENT emoji (White Heart). Editors hide the missing VS16, so assert on
  // codepoints. Locks both data traps out of the curated emote lists.
  const redHeart = '\u2764\uFE0F';

  group('curated emote codepoint integrity', () {
    test('suggested-emoji red heart carries the VS16 selector', () {
      expect(kFireplaceSuggestedEmoji, contains(redHeart));
    });

    test('no suggested emoji uses a bare U+2764 or the White Heart', () {
      for (final emote in kFireplaceSuggestedEmoji) {
        final units = emote.runes.toList();
        expect(
          units,
          isNot(contains(0x1F90D)),
          reason: 'U+1F90D White Heart found in "$emote"',
        );
        for (var i = 0; i < units.length; i++) {
          if (units[i] == 0x2764) {
            expect(
              i + 1 < units.length && units[i + 1] == 0xFE0F,
              isTrue,
              reason: 'U+2764 without the required U+FE0F in "$emote"',
            );
          }
        }
      }
    });
  });

  group('color-emoji font application', () {
    // The real root cause of the white heart: emoji Text inherits the ambient
    // Inter font, whose monochrome U+2764 glyph wins on Flutter-web CanvasKit
    // (VS16 ignored). The fix forces an emoji family as PRIMARY.
    test('withEmojiFont sets an emoji family as primary + fallbacks', () {
      final style = withEmojiFont(const TextStyle(fontFamily: 'Inter'));
      expect(style.fontFamily, kEmojiFontFamily);
      expect(style.fontFamilyFallback, kEmojiFontFamilyFallback);
      expect(kEmojiFontFamily, isNot('Inter'));
    });

    test('inline spans render emoji with the emoji font, text with the base', () {
      const base = TextStyle(fontFamily: 'Inter', fontSize: 14);
      final spans = buildInlineEmojiSpans('hi $redHeart', textStyle: base)
          .whereType<TextSpan>()
          .toList();

      final emojiSpan = spans.firstWhere((s) => s.text!.contains('\u2764'));
      final textSpan = spans.firstWhere((s) => s.text!.contains('hi'));

      expect(emojiSpan.style!.fontFamily, kEmojiFontFamily);
      expect(emojiSpan.style!.fontFamilyFallback, kEmojiFontFamilyFallback);
      expect(textSpan.style!.fontFamily, 'Inter');
    });
  });
}
