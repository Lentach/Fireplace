import 'web_viewport_scroll_stub.dart'
    if (dart.library.html) 'web_viewport_scroll_web.dart' as impl;

/// Resets host document scroll (web only). Safe no-op elsewhere.
void resetWebDocumentScroll() => impl.resetWebDocumentScroll();
