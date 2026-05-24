import 'web_viewport_scroll_stub.dart'
    if (dart.library.html) 'web_viewport_scroll_web.dart' as impl;

/// Clears accidental host document scroll (web only). Safe no-op elsewhere.
void resetWebDocumentScroll() => impl.resetWebDocumentScroll();

/// Locks or unlocks host-page scroll on iOS Safari PWA when the composer focuses.
void setIOSWebViewportScrollLocked(bool locked) =>
    impl.setIOSWebViewportScrollLocked(locked);
