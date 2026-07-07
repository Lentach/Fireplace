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

/// Storage key for the last real keyboard inset seen on this device, tagged
/// with the visual-viewport width it was measured at (`width:inset`).
/// Feeds [lastKnownKeyboardInset] so the composer flash-fix pre-arm works from
/// the first focus of a session (keyboard height is near-constant per device).
const String _kLastInsetStorageKey = 'composer_kb_inset_v1';

double _lastKnownInset = 0;
bool _lastKnownLoaded = false;

/// Last real keyboard inset observed on this device (persisted across
/// sessions), or 0 when unknown / not iOS WebKit / measured at a different
/// viewport width. Bounds-checked against [kMinKeyboardInset]..600 so corrupt
/// storage can never pre-arm a nonsense layout.
double lastKnownKeyboardInset() {
  if (!isIOSWebKit()) return 0;
  if (!_lastKnownLoaded) {
    _lastKnownLoaded = true;
    _lastKnownInset = _readPersistedInset();
  }
  return _lastKnownInset;
}

double _readPersistedInset() {
  try {
    final raw = web.window.localStorage.getItem(_kLastInsetStorageKey);
    if (raw == null) return 0;
    final parts = raw.split(':');
    if (parts.length != 2) return 0;
    final width = double.tryParse(parts[0]);
    final inset = double.tryParse(parts[1]);
    if (width == null || inset == null) return 0;
    final vvWidth = web.window.visualViewport?.width ?? 0;
    if ((width - vvWidth).abs() > 1) return 0;
    if (inset <= kMinKeyboardInset || inset > 600) return 0;
    return inset;
  } catch (_) {
    // Storage unavailable (private mode quirks): prediction just stays off.
    return 0;
  }
}

void _persistLastKnownInset(double inset, double width) {
  _lastKnownLoaded = true;
  if (inset == _lastKnownInset) return;
  _lastKnownInset = inset;
  try {
    web.window.localStorage.setItem(
      _kLastInsetStorageKey,
      '${width.round()}:${inset.round()}',
    );
  } catch (_) {
    // Best-effort; in-memory value still serves this session.
  }
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
    if (result.inset > 0) _persistLastKnownInset(result.inset, vv.width);
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
