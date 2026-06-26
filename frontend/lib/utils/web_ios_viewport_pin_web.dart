import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';

/// One pinned element plus a snapshot of the inline styles we override, so the
/// pin reverts to the EXACT prior state (Flutter owns `<flutter-view>`'s styles,
/// so we must not clobber them permanently — only overlay while focused).
///
/// [fixed] elements (`<body>`, `<flutter-view>`) are `position: fixed` and
/// offset by the visual-viewport pan to keep the scene aligned with the visible
/// area. `<html>` is clip-only (no reposition — `position: fixed` on the root is
/// fragile) so the document simply has no overflow for iOS to scroll.
class _PinnedElement {
  _PinnedElement(this.el, {required this.fixed})
      : _position = el.style.position,
        _top = el.style.top,
        _left = el.style.left,
        _width = el.style.width,
        _height = el.style.height,
        _overflow = el.style.overflow,
        _overscrollBehavior = el.style.overscrollBehavior;

  final web.HTMLElement el;
  final bool fixed;
  final String _position;
  final String _top;
  final String _left;
  final String _width;
  final String _height;
  final String _overflow;
  final String _overscrollBehavior;

  void apply(String top, String left, String width, String height) {
    final style = el.style;
    style.height = height;
    style.overflow = 'hidden';
    style.overscrollBehavior = 'none';
    if (fixed) {
      style.position = 'fixed';
      style.top = top;
      style.left = left;
      style.width = width;
    }
  }

  void restore() {
    final style = el.style
      ..position = _position
      ..top = _top
      ..left = _left
      ..width = _width
      ..height = _height
      ..overflow = _overflow;
    style.overscrollBehavior = _overscrollBehavior;
  }
}

bool _active = false;
JSFunction? _listener;
final List<_PinnedElement> _pinned = <_PinnedElement>[];

List<_PinnedElement> _collectTargets() {
  final targets = <_PinnedElement>[];
  if (web.document.documentElement case final web.HTMLElement root) {
    targets.add(_PinnedElement(root, fixed: false));
  }
  if (web.document.body case final web.HTMLElement body) {
    targets.add(_PinnedElement(body, fixed: true));
  }
  if (web.document.querySelector('flutter-view') case final web.HTMLElement fv) {
    targets.add(_PinnedElement(fv, fixed: true));
  }
  return targets;
}

void setIOSComposerViewportPin(bool active) {
  if (!isIOSWebKit()) return;
  final vv = web.window.visualViewport;
  if (vv == null) return;
  if (active == _active) return;
  _active = active;

  if (active) {
    _pinned
      ..clear()
      ..addAll(_collectTargets());
    final listener = ((web.Event _) => _apply()).toJS;
    _listener = listener;
    vv.addEventListener('resize', listener);
    vv.addEventListener('scroll', listener);
    _apply();
  } else {
    final listener = _listener;
    if (listener != null) {
      vv.removeEventListener('resize', listener);
      vv.removeEventListener('scroll', listener);
      _listener = null;
    }
    for (final element in _pinned) {
      element.restore();
    }
    _pinned.clear();
  }
}

void _apply() {
  if (!_active) return;
  final vv = web.window.visualViewport;
  if (vv == null) return;
  final height = '${vv.height}px';
  final width = '${vv.width}px';
  final top = '${vv.offsetTop}px';
  final left = '${vv.offsetLeft}px';

  for (final element in _pinned) {
    element.apply(top, left, width, height);
  }

  // Zero any host-document scroll iOS applied while bringing the input into view
  // (the pin removes the overflow, but a scroll may already have landed).
  if (web.document.documentElement case final web.HTMLElement root) {
    root.scrollTop = 0;
    root.scrollLeft = 0;
  }
  if (web.document.body case final web.HTMLElement body) {
    body.scrollTop = 0;
    body.scrollLeft = 0;
  }
}
