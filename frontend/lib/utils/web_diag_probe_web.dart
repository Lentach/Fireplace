import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Reads the live web-layer values that distinguish the candidate causes of the
/// keyboard-on action-panel bug:
///  - `active`        : DOM `document.activeElement` tag (+ `ce` if contentEditable).
///                      Shows whether iOS still considers an editable focused at
///                      the moment of the tap (focus-guard / blur question).
///  - `vv.offTop/h`   : `visualViewport.offsetTop` / `height` — iOS scrolls the
///                      visual viewport to keep a refocused field visible.
///  - `win.scrollY`   : layout-viewport scroll iOS may apply.
///  - `doc.scrollTop` : documentElement scroll (what resetWebDocumentScroll zeroes).
///  - `win.innerH`    : layout viewport height for reference.
Map<String, String> readWebDiagProbe() {
  final m = <String, String>{};

  final active = web.document.activeElement;
  if (active == null) {
    m['active'] = 'null';
  } else {
    var label = active.tagName;
    if (active.isA<web.HTMLElement>() &&
        (active as web.HTMLElement).isContentEditable) {
      label = '$label ce';
    }
    m['active'] = label;
  }

  final vv = web.window.visualViewport;
  if (vv != null) {
    m['vv.offTop'] = vv.offsetTop.round().toString();
    m['vv.h'] = vv.height.round().toString();
  } else {
    m['vv.offTop'] = '-';
    m['vv.h'] = '-';
  }

  m['win.scrollY'] = web.window.scrollY.round().toString();

  final root = web.document.documentElement;
  m['doc.scrollTop'] = root != null ? root.scrollTop.round().toString() : '-';

  m['win.innerH'] = web.window.innerHeight.toString();

  return m;
}
