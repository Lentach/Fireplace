/// (lxxvii) clause 3 — the in-app QR scanner, one facade, three impls:
///
/// - `link_qr_scanner_native.dart` (dart:io): `mobile_scanner`
///   (CameraX/ML Kit on Android, AVFoundation/Vision on iOS), QR only.
/// - `link_qr_scanner_web.dart` (dart:js_interop): our OWN `getUserMedia` +
///   `<video>` loop decoding via `BarcodeDetector` where the browser has it,
///   else the vendored `web/jsqr.js` — NEVER a runtime CDN (mobile_scanner's
///   web impl fetches ZXing at runtime, which is why it is not used here).
/// - `link_qr_scanner_stub.dart`: unsupported everywhere else.
///
/// Shared contract (every impl):
///
/// ```dart
/// LinkQrScanner({required void Function(String code) onCode,
///                VoidCallback? onUnsupported})
/// Future<bool> linkQrScanSupported()
/// ```
///
/// `onCode` fires AT MOST ONCE with the raw decoded text (callers normalize
/// with `extractLinkCode` and validate with `LinkOobCode.tryParse`).
/// `onUnsupported` fires when scanning cannot run here — no camera API,
/// permission denied, no decoder — and the widget renders NOTHING; the caller
/// falls back to the typed field, which always stays.
library;

export 'link_qr_scanner_stub.dart'
    if (dart.library.js_interop) 'link_qr_scanner_web.dart'
    if (dart.library.io) 'link_qr_scanner_native.dart';
