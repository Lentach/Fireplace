import 'package:flutter/foundation.dart';

import 'web_keyboard_inset.dart';

/// Off-web: no visualViewport. Inactive source whose inset stays 0, so callers
/// fall back to `MediaQuery.viewInsets.bottom`.
KeyboardInsetSource createKeyboardInsetSource() =>
    _InactiveKeyboardInsetSource();

class _InactiveKeyboardInsetSource implements KeyboardInsetSource {
  final ValueNotifier<double> _inset = ValueNotifier<double>(0);

  @override
  ValueListenable<double> get inset => _inset;

  @override
  bool get isActive => false;

  @override
  void dispose() => _inset.dispose();
}

/// Off-web there is no persisted keyboard measurement; prediction stays off.
double lastKnownKeyboardInset() => 0;
