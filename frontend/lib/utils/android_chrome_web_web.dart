import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

bool _cachedIsAndroidChromeWeb = false;
bool _didDetectAndroidChromeWeb = false;

/// Android Chrome tab/PWA only: requires `android` + `chrome` in UA and excludes
/// `edg` (Edge). Samsung Internet, Firefox, and other WebViews may not match.
bool isAndroidChromeWeb() {
  if (_didDetectAndroidChromeWeb) return _cachedIsAndroidChromeWeb;
  _didDetectAndroidChromeWeb = true;
  final ua = web.window.navigator.userAgent.toLowerCase();
  _cachedIsAndroidChromeWeb =
      ua.contains('android') && ua.contains('chrome') && !ua.contains('edg');
  return _cachedIsAndroidChromeWeb;
}

final ValueNotifier<int> _viewportEpoch = ValueNotifier<int>(0);

Listenable get androidChromeWebViewportListenable => _viewportEpoch;

double? readVisualViewportKeyboardInset() {
  final vv = web.window.visualViewport;
  if (vv == null) return null;
  final innerHeight = web.window.innerHeight.toDouble();
  final inset = innerHeight - vv.height - vv.offsetTop;
  if (inset.isNaN || inset.isInfinite || inset <= 0) return 0;
  return inset;
}

void resetBrowserViewportScroll() {
  final root = web.document.documentElement;
  if (root != null) {
    root.scrollTop = 0;
    root.scrollLeft = 0;
  }
  final body = web.document.body;
  if (body != null) {
    body.scrollTop = 0;
    body.scrollLeft = 0;
  }
}

bool _guardsInstalled = false;

void installAndroidChromeWebKeyboardGuards() {
  if (_guardsInstalled || !isAndroidChromeWeb()) return;
  _guardsInstalled = true;

  void onViewportChange(web.Event _) {
    resetBrowserViewportScroll();
    _viewportEpoch.value++;
    WidgetsBinding.instance.scheduleFrame();
  }

  final handler = onViewportChange.toJS;
  final vv = web.window.visualViewport;
  vv?.addEventListener('resize', handler);
  vv?.addEventListener('scroll', handler);
  web.window.addEventListener('focusin', handler);
}

bool shouldDisableScaffoldResizeForKeyboard() => isAndroidChromeWeb();
