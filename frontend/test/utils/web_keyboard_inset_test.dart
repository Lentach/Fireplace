import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/web_keyboard_inset.dart'
    show capKeyboardInset, isChatKeyboardVisible, kWebPhantomKeyboardInsetFraction;

void main() {
  group('capKeyboardInset', () {
    test('returns zero when inset is zero', () {
      expect(capKeyboardInset(0, 800), 0);
    });

    test('caps inset above phantom threshold', () {
      expect(capKeyboardInset(500, 800), 800 * kWebPhantomKeyboardInsetFraction);
    });

    test('keeps inset below cap unchanged', () {
      expect(capKeyboardInset(300, 800), 300);
    });
  });

  group('isChatKeyboardVisible', () {
    test('false when inset is zero', () {
      final data = MediaQueryData(
        size: const Size(400, 800),
        viewInsets: EdgeInsets.zero,
      );
      expect(isChatKeyboardVisible(data), isFalse);
    });

    test('true when capped inset is positive', () {
      final data = MediaQueryData(
        size: const Size(400, 800),
        viewInsets: const EdgeInsets.only(bottom: 200),
      );
      expect(isChatKeyboardVisible(data), isTrue);
    });
  });
}
