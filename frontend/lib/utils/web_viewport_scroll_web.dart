import 'package:web/web.dart' as web;

import 'web_ios_webkit.dart';

void resetWebDocumentScroll() {
  final root = web.document.documentElement;
  if (root case web.HTMLElement el) {
    el.scrollTop = 0;
    el.scrollLeft = 0;
  }
  final body = web.document.body;
  if (body != null) {
    body.scrollTop = 0;
    body.scrollLeft = 0;
  }
}

void setIOSWebViewportScrollLocked(bool locked) {
  if (!isIOSWebKit()) return;
  final root = web.document.documentElement;
  final body = web.document.body;
  if (root case web.HTMLElement htmlEl) {
    htmlEl.style.overflow = locked ? 'hidden' : '';
    htmlEl.style.overscrollBehavior = locked ? 'none' : '';
  }
  if (body != null) {
    body.style.overflow = locked ? 'hidden' : '';
    body.style.overscrollBehavior = locked ? 'none' : '';
  }
  if (locked) {
    resetWebDocumentScroll();
  }
}
