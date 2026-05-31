import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Reads the live web-layer values that distinguish the candidate causes of the
/// keyboard-on action-panel bug, as a compact one-liner:
///  - `active` : `document.activeElement` tag (+`ce` if contentEditable) — shows
///               whether iOS still considers an editable focused.
///  - `vv.off` / `vv.h` : `visualViewport.offsetTop` / `height` — iOS scrolls the
///               visual viewport to keep a refocused field visible.
///  - `sY`     : `window.scrollY` (layout-viewport scroll).
///  - `dT`     : `documentElement.scrollTop` (what resetWebDocumentScroll zeroes).
String composerProbeString() {
  final active = web.document.activeElement;
  String activeLabel;
  if (active == null) {
    activeLabel = 'null';
  } else {
    activeLabel = active.tagName;
    if (active.isA<web.HTMLElement>() &&
        (active as web.HTMLElement).isContentEditable) {
      activeLabel = '$activeLabel.ce';
    }
  }

  final vv = web.window.visualViewport;
  final vvOff = vv != null ? vv.offsetTop.round().toString() : '-';
  final vvH = vv != null ? vv.height.round().toString() : '-';

  final scrollY = web.window.scrollY.round();
  final root = web.document.documentElement;
  final docTop = root != null ? root.scrollTop.round().toString() : '-';

  return 'active=$activeLabel vv.off=$vvOff vv.h=$vvH sY=$scrollY dT=$docTop';
}
