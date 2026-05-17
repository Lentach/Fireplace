import 'package:flutter/widgets.dart';

import 'android_chrome_web_stub.dart'
    if (dart.library.html) 'android_chrome_web_web.dart' as impl;
import 'keyboard_inset_math.dart';

export 'keyboard_inset_math.dart' show resolveAndroidChromeWebKeyboardInset;

/// Widget tests: force Android Chrome Web keyboard path on VM (stub impl).
@visibleForTesting
bool? debugForceAndroidChromeWebKeyboardPath;

/// Widget tests: simulate [visualViewport] keyboard inset without a browser.
@visibleForTesting
double? debugVisualViewportKeyboardInset;

/// True on Android Chrome / WebView tab and PWA (not native Android app).
bool get isAndroidChromeWeb => impl.isAndroidChromeWeb();

/// Scaffold [resizeToAvoidBottomInset] fights phantom insets on Android Chrome Web.
bool get shouldDisableScaffoldResizeForKeyboard =>
    debugForceAndroidChromeWebKeyboardPath ??
    impl.shouldDisableScaffoldResizeForKeyboard();

double? get visualViewportKeyboardInset =>
    debugVisualViewportKeyboardInset ?? impl.readVisualViewportKeyboardInset();

void resetBrowserViewportScroll() => impl.resetBrowserViewportScroll();

void installAndroidChromeWebKeyboardGuards() =>
    impl.installAndroidChromeWebKeyboardGuards();

/// Fires when [visualViewport] changes on Android Chrome Web so composer padding
/// rebuilds even if [MediaQuery.viewInsets] lags a frame.
Listenable get androidChromeWebViewportListenable =>
    impl.androidChromeWebViewportListenable;

/// Keyboard height for chat auto-scroll and similar (matches composer lift).
double resolvedKeyboardInsetForContext(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  final layoutHeight = mediaQuery.size.height;
  final viewInsetsBottom = mediaQuery.viewInsets.bottom;
  if (!shouldDisableScaffoldResizeForKeyboard) {
    return viewInsetsBottom;
  }
  return resolveAndroidChromeWebKeyboardInset(
    viewInsetsBottom: viewInsetsBottom,
    layoutHeight: layoutHeight,
    visualViewportKeyboardInset: visualViewportKeyboardInset,
  );
}
