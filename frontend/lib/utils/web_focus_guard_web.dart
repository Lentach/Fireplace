import 'dart:js_interop';

import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';

final Map<String, Rect> _rects = <String, Rect>{};
bool _installed = false;
JSFunction? _downListener;

// Blur listener attached directly to the active textarea when a guarded-area
// tap is detected. Calling .focus() synchronously inside the blur handler
// cancels the iOS keyboard-dismiss animation before it starts.
JSFunction? _blurListener;
web.HTMLElement? _guardedElement;

void ensureFocusGuardListenerInstalled() {
  if (_installed) return;
  if (!isIOSWebKit()) return;
  _installed = true;
  _downListener = _onPointerDownCapture.toJS;
  // passive: false is required so preventDefault() is allowed on touchstart.
  final opts = web.AddEventListenerOptions(capture: true, passive: false);
  web.window.addEventListener('touchstart', _downListener, opts);
  web.window.addEventListener('mousedown', _downListener, opts);
}

void registerFocusGuardRect(String id, Rect rect) {
  if (!isIOSWebKit()) return;
  _rects[id] = rect;
}

void unregisterFocusGuardRect(String id) {
  _rects.remove(id);
}

void _detachBlurListener() {
  if (_guardedElement != null && _blurListener != null) {
    _guardedElement!.removeEventListener('blur', _blurListener!);
  }
  _guardedElement = null;
  _blurListener = null;
}

void _onGuardedElementBlur(web.Event _) {
  final el = _guardedElement;
  _detachBlurListener();
  // Re-focus synchronously within the blur event — iOS treats this as
  // "still focused" and does not start the keyboard dismiss animation.
  el?.focus();
}

void _onPointerDownCapture(web.Event event) {
  // Clean up any listener from a prior tap that never triggered a blur.
  _detachBlurListener();

  // Only guard when there is an active editing session; first-focus taps
  // must still work normally (no guard area active → fall through).
  final active = web.document.activeElement;
  if (!_isEditable(active)) return;
  final point = _eventPoint(event);
  if (point == null) return;
  for (final rect in _rects.values) {
    if (rect.contains(point)) {
      if (active.isA<web.HTMLElement>()) {
        // Attach a one-shot blur listener BEFORE iOS fires the blur so we can
        // restore focus synchronously within the same event-processing chain.
        _guardedElement = active as web.HTMLElement;
        _blurListener = _onGuardedElementBlur.toJS;
        _guardedElement!.addEventListener('blur', _blurListener!);
      }
      // Prevent scroll/zoom and synthetic mouse events on the guarded tap.
      event.preventDefault();
      return;
    }
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
