import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/web_ios_composer_focus_mask.dart';

void main() {
  group('composerMaskCssColor', () {
    test('drops alpha and emits #rrggbb lowercase hex', () {
      // messagesAreaBg (dark default): 0xFF08081E.
      expect(composerMaskCssColor(const Color(0xFF08081E)), '#08081e');
      // messagesAreaBgLight: 0xFFFAF8F5.
      expect(composerMaskCssColor(const Color(0xFFFAF8F5)), '#faf8f5');
      // A semi-transparent colour still yields its opaque rgb (mask is opaque).
      expect(composerMaskCssColor(const Color(0x8017212B)), '#17212b');
    });

    test('pads single-digit channels to two hex digits', () {
      expect(composerMaskCssColor(const Color(0xFF000000)), '#000000');
      expect(composerMaskCssColor(const Color(0xFFFFFFFF)), '#ffffff');
      expect(composerMaskCssColor(const Color(0xFF010203)), '#010203');
    });
  });

  group('show/hide on VM', () {
    test('are safe no-ops off web', () {
      expect(() => showComposerFocusMask('#000000'), returnsNormally);
      expect(() => hideComposerFocusMask(), returnsNormally);
    });
  });
}
