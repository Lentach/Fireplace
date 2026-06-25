import 'dart:js_interop';
import 'dart:math' as math;

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

  // The full (pre-keyboard) layout height, tracked as a running max. iOS keeps
  // the *layout* viewport at the full height when the keyboard opens, but in a
  // standalone PWA `window.innerHeight` SHRINKS to the above-keyboard height, so
  // it can't be used live as the layout reference. Reset on a width change
  // (orientation), then re-captured.
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
    final vvHeight = vv.height;
    final vvWidth = vv.width;
    final innerHeight = web.window.innerHeight.toDouble();
    final clientHeight =
        (web.document.documentElement?.clientHeight ?? 0).toDouble();

    // Orientation change: drop the captured height and re-capture below.
    if ((vvWidth - _trackedWidth).abs() > 1) {
      _trackedWidth = vvWidth;
      _fullLayoutHeight = 0;
    }
    // Track the full layout height from every signal that reflects it:
    //  - innerHeight (full while the keyboard is down),
    //  - documentElement.clientHeight (the layout viewport; stays full),
    //  - vv.height + vv.offsetTop (the visual viewport's bottom edge in layout
    //    space; equals the layout height when the page is panned to the bottom).
    // A running max is safe: the keyboard only shrinks these, never grows the
    // true layout height (orientation is handled by the reset above).
    _fullLayoutHeight = math.max(
      _fullLayoutHeight,
      math.max(innerHeight, math.max(clientHeight, vvHeight + vv.offsetTop)),
    );

    // Keyboard occlusion in Flutter's (unshrunk) scene = full layout height minus
    // the above-keyboard visible height. NOT minus offsetTop: offsetTop is the
    // OS pan (countered by the viewport pin), not part of the keyboard height.
    final occluded = _fullLayoutHeight - vvHeight;
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
