import 'package:flutter/foundation.dart';

import 'web_keyboard_inset_stub.dart'
    if (dart.library.html) 'web_keyboard_inset_web.dart' as impl;

/// Tracks the iOS soft-keyboard height from `window.visualViewport`.
///
/// On iOS WebKit the keyboard shrinks the *visual* viewport but NOT the *layout*
/// viewport, and Flutter's `MediaQuery.viewInsets.bottom` reads 0 even while the
/// keyboard is up (confirmed on-device: viewInsets=0 while visualViewport.height
/// was 394 → a ~403px keyboard Flutter never saw). This source computes the real
/// inset as `fullLayoutHeight - visualViewport.height`, where `fullLayoutHeight`
/// is the pre-keyboard layout height (a running max of `innerHeight`,
/// `documentElement.clientHeight`, and the panned visual-viewport bottom edge).
/// `window.innerHeight` alone is NOT used as the reference because a standalone
/// PWA shrinks it to the above-keyboard height. Updates on visualViewport
/// resize/scroll.
///
/// [isActive] is true only on iOS WebKit (web); elsewhere [inset] stays 0 so
/// callers can keep using `MediaQuery.viewInsets.bottom`.
abstract class KeyboardInsetSource {
  ValueListenable<double> get inset;
  bool get isActive;
  void dispose();
}

KeyboardInsetSource createKeyboardInsetSource() =>
    impl.createKeyboardInsetSource();
