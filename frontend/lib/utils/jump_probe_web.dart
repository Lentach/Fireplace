import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';

// TEMP diagnostic for the iOS "screen jumps up on composer focus" bug. A DOM
// overlay pinned to the VISUAL viewport (so it stays visible even while the page
// scrolls/pans), showing whether the shift is a DOCUMENT scroll (`sT`/`sY` > 0,
// resettable) or a VISUAL-VIEWPORT pan (`vvOff` > 0, not resettable from JS).
// Remove (this file + facade + the install/remove calls in
// `chat_composer_viewport.dart`) once the cause is captured.

web.HTMLElement? _box;
Timer? _timer;
JSFunction? _reposition;
int _maxScroll = 0;
int _maxVvOff = 0;

void installJumpProbe() {
  if (!isIOSWebKit()) return;
  if (_box != null) return;
  final box = web.document.createElement('div') as web.HTMLElement;
  box.id = 'jump-probe';
  box.style.cssText =
      'position:fixed;left:0;right:0;z-index:2147483647;'
      'background:rgba(0,0,0,0.82);color:#7CFFB2;'
      'font:11px/1.35 monospace;padding:4px 6px;pointer-events:none;'
      'white-space:pre-wrap;text-align:left;';
  web.document.body?.appendChild(box);
  _box = box;
  _maxScroll = 0;
  _maxVvOff = 0;

  void reposition() {
    final vv = web.window.visualViewport;
    box.style.top = '${(vv?.offsetTop ?? 0).round()}px';
    box.style.left = '${(vv?.offsetLeft ?? 0).round()}px';
  }

  _reposition = ((web.Event _) => reposition()).toJS;
  final vv = web.window.visualViewport;
  if (vv != null) {
    vv.addEventListener('scroll', _reposition!);
    vv.addEventListener('resize', _reposition!);
  }

  _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
    final root = web.document.documentElement;
    final body = web.document.body;
    final vv2 = web.window.visualViewport;
    final sT = (root?.scrollTop ?? 0).round();
    final bT = (body?.scrollTop ?? 0).round();
    final sY = web.window.scrollY.round();
    final vvOff = (vv2?.offsetTop ?? 0).round();
    final vvH = (vv2?.height ?? 0).round();
    final iH = web.window.innerHeight;
    final act = web.document.activeElement?.tagName ?? 'null';
    final scroll = [sT, bT, sY].reduce((a, b) => a > b ? a : b);
    if (scroll > _maxScroll) _maxScroll = scroll;
    if (vvOff > _maxVvOff) _maxVvOff = vvOff;
    box.textContent =
        'JUMP  sT=$sT bT=$bT sY=$sY  vvOff=$vvOff vvH=$vvH iH=$iH act=$act\n'
        'PEAK  scroll=$_maxScroll  vvOff=$_maxVvOff   '
        '(scroll>0 ⇒ document; vvOff>0 ⇒ visual-pan)';
    reposition();
  });
}

void removeJumpProbe() {
  _timer?.cancel();
  _timer = null;
  final vv = web.window.visualViewport;
  if (vv != null && _reposition != null) {
    vv.removeEventListener('scroll', _reposition!);
    vv.removeEventListener('resize', _reposition!);
  }
  _reposition = null;
  _box?.remove();
  _box = null;
}
