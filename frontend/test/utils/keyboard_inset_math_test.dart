import 'package:fireplace/utils/keyboard_inset_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAndroidChromeWebKeyboardInset', () {
    const layoutHeight = 800.0;

    test('returns 0 when both signals are zero', () {
      expect(
        resolveAndroidChromeWebKeyboardInset(
          viewInsetsBottom: 0,
          layoutHeight: layoutHeight,
          visualViewportKeyboardInset: 0,
        ),
        0,
      );
    });

    test('prefers visual viewport when MediaQuery inset is suspiciously large', () {
      expect(
        resolveAndroidChromeWebKeyboardInset(
          viewInsetsBottom: 700,
          layoutHeight: layoutHeight,
          visualViewportKeyboardInset: 320,
        ),
        320,
      );
    });

    test('caps suspicious MediaQuery inset when visual viewport lags at 0', () {
      expect(
        resolveAndroidChromeWebKeyboardInset(
          viewInsetsBottom: 700,
          layoutHeight: layoutHeight,
        ),
        layoutHeight * 0.45,
      );
    });

    test('uses max of normal-sized inset and visual viewport', () {
      expect(
        resolveAndroidChromeWebKeyboardInset(
          viewInsetsBottom: 280,
          layoutHeight: layoutHeight,
          visualViewportKeyboardInset: 300,
        ),
        300,
      );
    });
  });

  group('composerBottomInteractivePadding', () {
    test('lifts composer on Android Chrome Web when keyboard is visible', () {
      expect(
        composerBottomInteractivePadding(
          androidChromeWebComposerLift: true,
          keyboardVisible: true,
          viewInsetsBottom: 700,
          layoutHeight: 800,
          visualViewportKeyboardInset: 320,
          bottomSystemInset: 0,
          webMobileFallbackNeeded: false,
          webMobileFallbackInset: 0,
        ),
        320,
      );
    });

    test('uses capped mq fallback when vv lags but keyboard is visible', () {
      expect(
        composerBottomInteractivePadding(
          androidChromeWebComposerLift: true,
          keyboardVisible: true,
          viewInsetsBottom: 700,
          layoutHeight: 800,
          visualViewportKeyboardInset: 0,
          bottomSystemInset: 0,
          webMobileFallbackNeeded: false,
          webMobileFallbackInset: 0,
        ),
        360,
      );
    });

    test('returns 0 on other platforms when keyboard is visible', () {
      expect(
        composerBottomInteractivePadding(
          androidChromeWebComposerLift: false,
          keyboardVisible: true,
          viewInsetsBottom: 320,
          layoutHeight: 800,
          visualViewportKeyboardInset: null,
          bottomSystemInset: 0,
          webMobileFallbackNeeded: false,
          webMobileFallbackInset: 0,
        ),
        0,
      );
    });

    test('keeps ergonomic buffer when keyboard is hidden', () {
      expect(
        composerBottomInteractivePadding(
          androidChromeWebComposerLift: true,
          keyboardVisible: false,
          viewInsetsBottom: 0,
          layoutHeight: 800,
          visualViewportKeyboardInset: 0,
          bottomSystemInset: 34,
          webMobileFallbackNeeded: false,
          webMobileFallbackInset: 0,
        ),
        50,
      );
    });
  });
}
