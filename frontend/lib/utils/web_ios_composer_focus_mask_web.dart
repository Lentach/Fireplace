import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';

// Solid cosmetic mask covering the whole scene during the iOS-WebKit composer
// focus transient. On focus iOS scrolls the document + pans the visual viewport
// (by the keyboard height) to drag Flutter's below-fold editing <textarea> into
// view — that pan/scroll is the visible "flash". The viewport pin
// (web_ios_viewport_pin) counters it reactively from the main thread, always a
// frame behind the GPU compositor, so it can only *undo* the jump after it
// happens, never prevent it: the residual gap before the undo IS the flash.
//
// This mask sidesteps that entirely: a full-scene solid fill in the app
// background colour, painted from the first touch and faded out once the visual
// viewport has settled (keyboard up + offsetTop reconciled to ~0) or after a
// safety timeout. A solid full-scene fill needs no frame-perfect tracking, so
// the compositor lag stops mattering — the jump still happens, underneath,
// invisibly. position:fixed + full layout-viewport height ⇒ the visible window
// is always a sub-rect of the fill regardless of the OS pan.

const int _kMaxVisibleMs = 600; // safety fade even if settle is never detected
const int _kFadeMs = 140;
const double _kKeyboardUpDeltaPx = 80.0; // vv shrink that means "keyboard up"
const double _kPanSettledPx = 3.0; // offsetTop back to ~0 ⇒ pin has reconciled
// Just below jump_probe's z-index so the diagnostic stays readable on device.
const String _kZIndex = '2147483640';

web.HTMLElement? _mask;
JSFunction? _settleListener;
Timer? _safetyTimer;
Timer? _fadeRemoveTimer;
double _vvHeightAtShow = 0;
bool _fading = false;

void showComposerFocusMask(String cssColor) {
  if (!isIOSWebKit()) return;
  final vv = web.window.visualViewport;
  if (vv == null) return;
  if (_mask != null) return; // already shown — keep the existing fill

  _fading = false;
  _vvHeightAtShow = vv.height;

  final mask = web.document.createElement('div') as web.HTMLElement;
  mask.id = 'composer-focus-mask';
  mask.style.cssText =
      'position:fixed;top:0;left:0;right:0;bottom:0;'
      'z-index:$_kZIndex;background:$cssColor;opacity:1;pointer-events:none;'
      'transition:opacity ${_kFadeMs}ms linear;';
  // Explicit full-scene height so the fill spans the whole (unshrunk) layout
  // viewport, not just the keyboard-shrunk window — covers the visible area in
  // every pan state. Mirrors web_keyboard_inset's fullLayoutHeight signals.
  final fullHeight = <double>[
    web.window.innerHeight.toDouble(),
    (web.document.documentElement?.clientHeight ?? 0).toDouble(),
    vv.height + vv.offsetTop,
  ].reduce((a, b) => a > b ? a : b);
  mask.style.height = '${fullHeight.ceil()}px';
  mask.style.minHeight = '${fullHeight.ceil()}px';

  web.document.body?.appendChild(mask);
  _mask = mask;

  final listener = ((web.Event _) => _maybeSettle()).toJS;
  _settleListener = listener;
  vv.addEventListener('resize', listener);
  vv.addEventListener('scroll', listener);

  _safetyTimer =
      Timer(const Duration(milliseconds: _kMaxVisibleMs), _fadeOut);
}

void _maybeSettle() {
  if (_mask == null || _fading) return;
  final vv = web.window.visualViewport;
  if (vv == null) return;
  final keyboardUp = (_vvHeightAtShow - vv.height) > _kKeyboardUpDeltaPx;
  final panReconciled = vv.offsetTop <= _kPanSettledPx;
  if (keyboardUp && panReconciled) _fadeOut();
}

void _fadeOut() {
  final mask = _mask;
  if (mask == null || _fading) return;
  _fading = true;
  _detachSettleListener();
  _safetyTimer?.cancel();
  _safetyTimer = null;
  mask.style.opacity = '0';
  _fadeRemoveTimer =
      Timer(const Duration(milliseconds: _kFadeMs + 40), _removeNow);
}

void hideComposerFocusMask() => _removeNow();

void _removeNow() {
  _detachSettleListener();
  _safetyTimer?.cancel();
  _safetyTimer = null;
  _fadeRemoveTimer?.cancel();
  _fadeRemoveTimer = null;
  _fading = false;
  _mask?.remove();
  _mask = null;
}

void _detachSettleListener() {
  final vv = web.window.visualViewport;
  final listener = _settleListener;
  if (vv != null && listener != null) {
    vv.removeEventListener('resize', listener);
    vv.removeEventListener('scroll', listener);
  }
  _settleListener = null;
}
