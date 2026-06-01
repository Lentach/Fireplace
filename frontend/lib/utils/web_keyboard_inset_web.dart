import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';
import 'web_keyboard_inset.dart';

/// Insets smaller than this are treated as 0 — rounding / safe-area noise. A real
/// soft keyboard is always far taller (~250px+).
const double _kMinKeyboardInset = 80.0;

KeyboardInsetSource createKeyboardInsetSource() {
  if (isIOSWebKit()) return _VisualViewportKeyboardInsetSource();
  return _InactiveKeyboardInsetSource();
}

class _InactiveKeyboardInsetSource implements KeyboardInsetSource {
  final ValueNotifier<double> _inset = ValueNotifier<double>(0);

  @override
  ValueListenable<double> get inset => _inset;

  @override
  bool get isActive => false;

  @override
  void dispose() => _inset.dispose();
}

class _VisualViewportKeyboardInsetSource implements KeyboardInsetSource {
  _VisualViewportKeyboardInsetSource() {
    // One JSFunction reused for add + remove (a fresh .toJS each time would not
    // match on removeEventListener).
    _listener = ((web.Event _) => _recompute()).toJS;
    final vv = web.window.visualViewport;
    if (vv != null) {
      vv.addEventListener('resize', _listener);
      vv.addEventListener('scroll', _listener);
    }
    _recompute();
  }

  final ValueNotifier<double> _inset = ValueNotifier<double>(0);
  late final JSFunction _listener;

  @override
  ValueListenable<double> get inset => _inset;

  @override
  bool get isActive => true;

  void _recompute() {
    final vv = web.window.visualViewport;
    if (vv == null) {
      _inset.value = 0;
      return;
    }
    final layoutHeight = web.window.innerHeight.toDouble();
    final occluded = layoutHeight - vv.height - vv.offsetTop;
    _inset.value = occluded > _kMinKeyboardInset ? occluded : 0;
  }

  @override
  void dispose() {
    final vv = web.window.visualViewport;
    if (vv != null) {
      vv.removeEventListener('resize', _listener);
      vv.removeEventListener('scroll', _listener);
    }
    _inset.dispose();
  }
}
