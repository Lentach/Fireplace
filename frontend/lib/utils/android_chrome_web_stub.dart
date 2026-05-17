import 'package:flutter/foundation.dart';

bool isAndroidChromeWeb() => false;

double? readVisualViewportKeyboardInset() => null;

void resetBrowserViewportScroll() {}

void installAndroidChromeWebKeyboardGuards() {}

bool shouldDisableScaffoldResizeForKeyboard() => false;

/// Never notifies on non-web builds.
Listenable get androidChromeWebViewportListenable => _noopViewportListenable;

class _NoopViewportListenable implements Listenable {
  const _NoopViewportListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

const _noopViewportListenable = _NoopViewportListenable();
