import 'dart:js_interop';

import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';

final Map<String, Rect> _rects = <String, Rect>{};
bool _installed = false;
JSFunction? _listener;

void ensureFocusGuardListenerInstalled() {
  if (_installed) return;
  if (!isIOSWebKit()) return;
  _installed = true;
  _listener = _onPointerDownCapture.toJS;
  // passive: false is required so preventDefault() is allowed on touchstart.
  final options = web.AddEventListenerOptions(capture: true, passive: false);
  web.window.addEventListener('touchstart', _listener, options);
  web.window.addEventListener('mousedown', _listener, options);
}

void registerFocusGuardRect(String id, Rect rect) {
  if (!isIOSWebKit()) return;
  _rects[id] = rect;
}

void unregisterFocusGuardRect(String id) {
  _rects.remove(id);
}

void _onPointerDownCapture(web.Event event) {
  // Only protect an active editing session; otherwise let the tap behave normally
  // (e.g. first focus on the field must still work).
  if (!_isEditable(web.document.activeElement)) return;
  final point = _eventPoint(event);
  if (point == null) return;
  for (final rect in _rects.values) {
    if (rect.contains(point)) {
      // Cancel WebKit's focus-steal so the input keeps focus and the keyboard
      // stays up. We do NOT stopPropagation, so Flutter still receives the tap.
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
