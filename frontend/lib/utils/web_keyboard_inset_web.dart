import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'keyboard_inset_math.dart';
import 'web_ios_webkit.dart';
import 'web_keyboard_inset.dart';

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

  // Running-max full layout height + the width it is valid for — see
  // `computeKeyboardInset` in keyboard_inset_math.dart for the rationale.
  double _fullLayoutHeight = 0;
  double _trackedWidth = 0;

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
    final result = computeKeyboardInset(
      previousFullLayoutHeight: _fullLayoutHeight,
      previousTrackedWidth: _trackedWidth,
      vvHeight: vv.height,
      vvWidth: vv.width,
      vvOffsetTop: vv.offsetTop,
      innerHeight: web.window.innerHeight.toDouble(),
      clientHeight: (web.document.documentElement?.clientHeight ?? 0)
          .toDouble(),
    );
    _fullLayoutHeight = result.fullLayoutHeight;
    _trackedWidth = result.trackedWidth;
    _inset.value = result.inset;
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
