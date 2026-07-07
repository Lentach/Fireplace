import 'dart:js_interop';

import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:web/web.dart' as web;

import '../widgets/input/composer_keyboard_signals.dart'
    show composerProbeDisableFocusGuard;
import 'web_ios_webkit.dart';

final Map<String, Rect> _rects = <String, Rect>{};
bool _installed = false;
JSFunction? _downListener;
JSFunction? _endListener;

// Active element saved on touchstart so touchend can restore focus inside the
// user-gesture context — the only place iOS Safari accepts .focus() calls.
web.Element? _savedElement;

void ensureFocusGuardListenerInstalled() {
  if (_installed) return;
  if (!isIOSWebKit()) return;
  _installed = true;
  _downListener = _onPointerDownCapture.toJS;
  _endListener = _onTouchEndCapture.toJS;
  // passive: false is required so preventDefault() is allowed.
  final opts = web.AddEventListenerOptions(capture: true, passive: false);
  web.window.addEventListener('touchstart', _downListener, opts);
  web.window.addEventListener('mousedown', _downListener, opts);
  web.window.addEventListener('touchend', _endListener, opts);
}

void registerFocusGuardRect(String id, Rect rect) {
  if (!isIOSWebKit()) return;
  _rects[id] = rect;
}

void unregisterFocusGuardRect(String id) {
  _rects.remove(id);
}

void _onPointerDownCapture(web.Event event) {
  _savedElement = null;
  // TEMP Phase-B probe: pass every pointer through untouched so the device
  // session can tell whether the guard is still load-bearing.
  if (composerProbeDisableFocusGuard.value) return;

  // Only protect an active editing session; first-focus taps must work normally.
  final active = web.document.activeElement;
  if (!_isEditable(active)) return;
  final point = _eventPoint(event);
  if (point == null) return;
  for (final rect in _rects.values) {
    if (rect.contains(point)) {
      _savedElement = active;
      event.preventDefault();
      return;
    }
  }
}

// touchend is a user-gesture context on iOS — .focus() called here is accepted
// by iOS and re-shows the keyboard. preventDefault stops iOS from synthesising
// a tap-focus-change (the click-based blur path).
void _onTouchEndCapture(web.Event event) {
  final el = _savedElement;
  _savedElement = null;
  if (el == null) return;
  event.preventDefault();
  if (el.isA<web.HTMLElement>()) {
    (el as web.HTMLElement).focus();
  }
}

bool _isEditable(web.Element? el) {
  if (el == null) return false;
  final tag = el.tagName.toUpperCase();
  if (tag == 'INPUT' || tag == 'TEXTAREA') return true;
  if (el.isA<web.HTMLElement>()) {
    return (el as web.HTMLElement).isContentEditable;
  }
  return false;
}

Offset? _eventPoint(web.Event event) {
  if (event.isA<web.TouchEvent>()) {
    final touches = (event as web.TouchEvent).touches;
    if (touches.length == 0) return null;
    final touch = touches.item(0);
    if (touch == null) return null;
    return Offset(touch.clientX.toDouble(), touch.clientY.toDouble());
  }
  if (event.isA<web.MouseEvent>()) {
    final m = event as web.MouseEvent;
    return Offset(m.clientX.toDouble(), m.clientY.toDouble());
  }
  return null;
}
