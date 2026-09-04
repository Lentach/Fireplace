import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS()
extension type _NavigatorStandalone(JSObject _) {
  external bool? get standalone;
}

/// Whether the PWA runs INSTALLED rather than in a plain browser tab
/// (multi-device amendment (lxxiv) clause 1).
///
/// The signal is `matchMedia('(display-mode: standalone)')` OR the iOS
/// Safari-only `navigator.standalone` — deliberately NOT
/// `navigator.storage.persisted()`: WebKit ≤ 16 has no such API and 17+
/// answers heuristically. Any engine quirk answers `false` (a wrong "tab"
/// shows an install instruction; a wrong "installed" would offer minting a
/// DAK into evictable storage).
bool isInstalledDisplayMode() {
  try {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    return _NavigatorStandalone(web.window.navigator as JSObject).standalone ==
        true;
  } catch (_) {
    return false;
  }
}
