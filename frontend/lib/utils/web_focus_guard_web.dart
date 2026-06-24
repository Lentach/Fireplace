import 'dart:js_interop';

import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';
import 'focus_guard_geometry.dart';

final Map<String, Rect> _rects = <String, Rect>{};
bool _installed = false;
JSFunction? _downListener;
JSFunction? _endListener;

// Active element saved on touchstart so touchend can restore focus inside the
// user-gesture context — the only place iOS Safari accepts .focus() calls.
web.Element? _savedElement;

// --- diagnostic ring buffer (Symptom C): records the focus/blur/guard sequence
// so a device capture shows whether the editable still blurs on a control tap.
final List<String> _events = <String>[];
final int _t0 = DateTime.now().millisecondsSinceEpoch;
JSFunction? _focusListener;

void _logEvent(String s) {
  final t = DateTime.now().millisecondsSinceEpoch - _t0;
  _events.add('$t ms $s');
  if (_events.length > 12) _events.removeAt(0);
}

/// Diagnostic-only: recent focus/blur/guard events (newest last); empty off iOS.
List<String> focusGuardEventLines() => List<String>.unmodifiable(_events);

String _targetTag(web.Event e) {
  final t = e.target;
  if (t != null && t.isA<web.Element>()) return (t as web.Element).tagName;
  return '?';
}

void ensureFocusGuardListenerInstalled() {
  if (_installed) return;
  if (!isIOSWebKit()) return;
  _installed = true;
  _downListener = _onPointerDownCapture.toJS;
  _endListener = _onTouchEndCapture.toJS;
  _focusListener =
      ((web.Event e) => _logEvent('${e.type == 'focusout' ? 'BLUR' : 'FOCUS'} ${_targetTag(e)}')).toJS;
  // passive: false is required so preventDefault() is allowed.
  final opts = web.AddEventListenerOptions(capture: true, passive: false);
  web.window.addEventListener('touchstart', _downListener, opts);
  web.window.addEventListener('mousedown', _downListener, opts);
  web.window.addEventListener('touchend', _endListener, opts);
  web.window.addEventListener('focusin', _focusListener!, opts);
  web.window.addEventListener('focusout', _focusListener!, opts);
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

  // Only protect an active editing session; first-focus taps must work normally.
  final active = web.document.activeElement;
  if (!_isEditable(active)) return;
  final point = _eventPoint(event);
  if (point == null) return;
  final hit =
      focusGuardPointHitsAnyRect(_rects.values, point, _visualViewportOffset());
  if (hit) {
    _savedElement = active;
    event.preventDefault();
  }
  _logEvent('${event.type} hit=$hit');
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
    _logEvent('touchend refocus');
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

// iOS offsets the visual viewport (not the document scroll) to keep a focused
// field visible while the keyboard is up, so a touch's clientX/Y can be in a
// different origin than the Flutter-registered rects. Expose that offset so the
// hit-test can also check the layout-space point.
Offset _visualViewportOffset() {
  final vv = web.window.visualViewport;
  if (vv == null) return Offset.zero;
  return Offset(vv.offsetLeft.toDouble(), vv.offsetTop.toDouble());
}
