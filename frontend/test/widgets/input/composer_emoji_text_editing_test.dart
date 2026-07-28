import 'package:fireplace/widgets/input/composer_emoji_text_editing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('composer emoji text editing', () {
    test(
      'insertEmojiAtSelection replaces the current selection and moves the caret',
      () {
        const value = TextEditingValue(
          text: 'hello world',
          selection: TextSelection(baseOffset: 6, extentOffset: 11),
        );

        final updated = insertEmojiAtSelection(value, '🔥');

        expect(updated.text, 'hello 🔥');
        expect(
          updated.selection,
          TextSelection.collapsed(offset: 'hello 🔥'.length),
        );
        expect(updated.composing, TextRange.empty);
      },
    );

    test(
      'deletePreviousEmojiGrapheme removes a full emoji sequence before the caret',
      () {
        const family = '👨‍👩‍👧‍👦';
        const tonedThumb = '👍🏽';
        final cases = [
          (
            name: 'family zwj sequence',
            value: TextEditingValue(
              text: 'A$family!',
              selection: TextSelection.collapsed(offset: 'A$family'.length),
            ),
            expectedText: 'A!',
            expectedOffset: 'A'.length,
          ),
          (
            name: 'skin-tone emoji sequence',
            value: TextEditingValue(
              text: 'Go $tonedThumb!',
              selection: TextSelection.collapsed(
                offset: 'Go $tonedThumb'.length,
              ),
            ),
            expectedText: 'Go !',
            expectedOffset: 'Go '.length,
          ),
        ];

        for (final c in cases) {
          final updated = deletePreviousEmojiGrapheme(c.value);

          expect(updated.text, c.expectedText, reason: c.name);
          expect(
            updated.selection,
            TextSelection.collapsed(offset: c.expectedOffset),
            reason: c.name,
          );
          expect(updated.composing, TextRange.empty, reason: c.name);
        }
      },
    );
  });
}
