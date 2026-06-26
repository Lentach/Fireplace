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
// This mask sidesteps that entirely: a full-scene solid fill painted from the
// first touch and faded out once the viewport has settled. position:fixed + full
// layout-viewport height ⇒ the visible window is always a sub-rect of the fill.

// DIAGNOSTIC MODE. While true the mask is bright magenta, fully opaque, and does
// NOT fade — it stays for the whole focus so it is impossible to miss and the
// jump_probe MASK line can read its live state. Flip to false for production
// (real app-bg colour + fade). See docs/review/ios-composer-keyboard-flash-*.
const bool kLoudComposerMaskDebug = true;

const int _kMaxVisibleMs = 600; // safety fade even if settle is never detected
const int _kFadeMs = 140;
const double _kKeyboardUpDeltaPx = 80.0; // vv shrink that means "keyboard up"
const double _kPanSettledPx = 3.0; // offsetTop back to ~0 ⇒ pin has reconciled
const String _kMaskId = 'composer-focus-mask';
// Just below jump_probe's z-index so the diagnostic stays readable on device.
const String _kZIndex = '2147483640';

web.HTMLElement? _mask;
JSFunction? _settleListener;
Timer? _safetyTimer;
Timer? _fadeRemoveTimer;
double _vvHeightAtShow = 0;
bool _fading = false;

// --- Diagnostics (read by jump_probe) -------------------------------------
int _showCalls = 0;
int _hideCalls = 0;
int _appended = 0;
String _lastOutcome = 'never';

void showComposerFocusMask(String cssColor) {
  _showCalls++;
  if (!isIOSWebKit()) {
    _lastOutcome = 'skip:notIOS';
    return;
  }
  final vv = web.window.visualViewport;
  if (vv == null) {
    _lastOutcome = 'skip:noVV';
    return;
  }
  if (_mask != null) {
    _lastOutcome = 'skip:exists';
    return; // already shown — keep the existing fill
  }

  _fading = false;
  _vvHeightAtShow = vv.height;

  final mask = web.document.createElement('div') as web.HTMLElement;
  mask.id = _kMaskId;
  final bg = kLoudComposerMaskDebug ? '#FF00FF' : cssColor;
  mask.style.cssText =
      'position:fixed;top:0;left:0;right:0;bottom:0;'
      'z-index:$_kZIndex;background:$bg;opacity:1;pointer-events:none;'
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
  _appended++;
  _lastOutcome = 'appended';

  // Loud diagnostic mode: never fade — stay up the whole focus so it can be seen
  // and measured. Only hideComposerFocusMask (blur / dispose) removes it.
  if (kLoudComposerMaskDebug) {
    // Keep it up long enough to see + let the probe read it, but never strand
    // the user: auto-remove after 2s regardless of settle.
    _safetyTimer = Timer(const Duration(milliseconds: 2000), _removeNow);
    return;
  }

  final listener = ((web.Event _) => _maybeSettle()).toJS;
  _settleListener = listener;
  vv.addEventListener('resize', listener);
  vv.addEventListener('scroll', listener);

  _safetyTimer = Timer(const Duration(milliseconds: _kMaxVisibleMs), _fadeOut);
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

void hideComposerFocusMask() {
  _hideCalls++;
  _removeNow();
}

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

/// Live diagnostic snapshot read from the real DOM, for the jump_probe overlay.
/// Tells us, in one line, whether the mask was called, appended, is in the DOM,
/// its computed styles + rect, and — decisively — what `elementFromPoint` at the
/// screen centre actually is (if not the mask, the mask is behind the canvas).
String composerFocusMaskDiag() {
  final el = web.document.getElementById(_kMaskId) as web.HTMLElement?;
  final buf = StringBuffer(
    'MASK call=$_showCalls add=$_appended hide=$_hideCalls out=$_lastOutcome',
  );
  if (el == null) {
    buf.write(' dom=N');
  } else {
    final cs = web.window.getComputedStyle(el);
    final r = el.getBoundingClientRect();
    buf.write(
      ' dom=Y op=${cs.opacity} z=${cs.zIndex} bg=${cs.backgroundColor}'
      ' r=${r.left.round()},${r.top.round()} ${r.width.round()}x${r.height.round()}',
    );
  }
  final cx = (web.window.innerWidth / 2).round();
  final cy = (web.window.innerHeight / 2).round();
  final top = web.document.elementFromPoint(cx.toDouble(), cy.toDouble());
  final tag = top?.tagName ?? 'null';
  final id = (top?.id.isNotEmpty ?? false) ? '#${top!.id}' : '';
  buf.write(' ctr@$cx,$cy=$tag$id');
  return buf.toString();
}
