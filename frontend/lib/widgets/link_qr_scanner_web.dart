import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web impl of `link_qr_scanner.dart`: our own `getUserMedia` preview in an
/// [HtmlElementView], decoded every ~150 ms from a canvas frame. Decoder
/// preference (amendment (lxxvii) clause 3): the browser's native
/// `BarcodeDetector` when it supports `qr_code`, else `jsQR` from the VENDORED
/// `web/jsqr.js` (`<script src="jsqr.js" defer>` in index.html) — never a
/// runtime CDN.

/// How often a frame is pulled off the video and decoded. A QR held to a
/// camera survives ~7 windows a second easily; decoding faster only burns CPU.
const _kDecodeInterval = Duration(milliseconds: 150);

/// Longest side of the frame handed to the decoder. jsQR is O(pixels); a
/// full 1080p frame costs ~6× this budget for zero range gain at arm's length.
const _kMaxDecodeSide = 640;

@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector(JSObject options);
  external static JSPromise<JSArray<JSString>> getSupportedFormats();
  external JSPromise<JSArray<_DetectedBarcode>> detect(JSAny source);
}

@JS()
extension type _DetectedBarcode._(JSObject _) implements JSObject {
  external String get rawValue;
}

@JS('jsQR')
external _JsQrResult? _jsQr(JSAny data, int width, int height);

@JS()
extension type _JsQrResult._(JSObject _) implements JSObject {
  external String get data;
}

bool get _hasMediaDevices => web.window.navigator.has('mediaDevices');

bool get _hasJsQr => globalContext.has('jsQR');

bool get _hasBarcodeDetector => globalContext.has('BarcodeDetector');

Future<bool> _barcodeDetectorReadsQr() async {
  if (!_hasBarcodeDetector) return false;
  try {
    final formats = (await _BarcodeDetector.getSupportedFormats().toDart)
        .toDart;
    return formats.any((f) => f.toDart == 'qr_code');
  } catch (_) {
    return false;
  }
}

/// True when this browser can run the scanner at all: a camera API plus at
/// least one decoder. Permission is NOT probed here — asking costs a prompt;
/// a denial surfaces through the widget's `onUnsupported` instead.
Future<bool> linkQrScanSupported() async {
  if (!_hasMediaDevices) return false;
  if (_hasJsQr) return true;
  return _barcodeDetectorReadsQr();
}

int _viewCounter = 0;

/// See `link_qr_scanner.dart` for the shared contract.
class LinkQrScanner extends StatefulWidget {
  const LinkQrScanner({super.key, required this.onCode, this.onUnsupported});

  final void Function(String code) onCode;
  final VoidCallback? onUnsupported;

  @override
  State<LinkQrScanner> createState() => _LinkQrScannerState();
}

class _LinkQrScannerState extends State<LinkQrScanner> {
  late final String _viewType;
  late final web.HTMLVideoElement _video;
  final web.HTMLCanvasElement _canvas = web.HTMLCanvasElement();

  web.MediaStream? _stream;
  _BarcodeDetector? _detector;
  bool _useJsQr = false;
  Timer? _timer;
  bool _decoding = false;
  bool _delivered = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'link-qr-scanner-${_viewCounter++}';
    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', '')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _video,
    );
    _start();
  }

  Future<void> _start() async {
    // Decoder first: a missing decoder must not cost a permission prompt.
    if (await _barcodeDetectorReadsQr()) {
      _detector = _BarcodeDetector(
        {
          'formats': ['qr_code'],
        }.jsify()! as JSObject,
      );
    } else if (_hasJsQr) {
      _useJsQr = true;
    } else {
      _unsupported();
      return;
    }
    if (!_hasMediaDevices) {
      _unsupported();
      return;
    }
    final web.MediaStream stream;
    try {
      stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              video: {'facingMode': 'environment'}.jsify()!,
            ),
          )
          .toDart;
    } catch (_) {
      // NotAllowedError (denied), NotFoundError (no camera), NotReadableError
      // (camera claimed elsewhere) — all mean "type the code instead".
      _unsupported();
      return;
    }
    if (!mounted || _delivered) {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
      return;
    }
    _stream = stream;
    _video.srcObject = stream;
    // play() can reject under autoplay policy; `autoplay` + a live camera
    // stream makes that unlikely, and a rejection alone is not fatal — the
    // decode loop simply never sees a ready frame until playback starts.
    try {
      await _video.play().toDart;
    } catch (_) {}
    _timer = Timer.periodic(_kDecodeInterval, (_) {
      _decodeTick();
    });
  }

  void _unsupported() {
    if (!mounted || _failed) return;
    setState(() => _failed = true);
    widget.onUnsupported?.call();
  }

  Future<void> _decodeTick() async {
    if (_decoding || _delivered || !mounted) return;
    // HAVE_CURRENT_DATA — the element has a decodable frame.
    if (_video.readyState < 2 || _video.videoWidth == 0) return;
    _decoding = true;
    try {
      final scale = math.min(
        1.0,
        _kMaxDecodeSide / math.max(_video.videoWidth, _video.videoHeight),
      );
      final w = (_video.videoWidth * scale).round();
      final h = (_video.videoHeight * scale).round();
      if (_canvas.width != w) _canvas.width = w;
      if (_canvas.height != h) _canvas.height = h;
      final ctx = _canvas.getContext('2d')! as web.CanvasRenderingContext2D;
      ctx.drawImage(_video, 0, 0, w, h);
      String? decoded;
      final detector = _detector;
      if (detector != null) {
        final found = (await detector.detect(_canvas).toDart).toDart;
        if (found.isNotEmpty) decoded = found.first.rawValue;
      } else if (_useJsQr) {
        final image = ctx.getImageData(0, 0, w, h);
        decoded = _jsQr(image.data, w, h)?.data;
      }
      if (decoded != null && decoded.isNotEmpty && !_delivered && mounted) {
        _delivered = true;
        _stopCamera();
        widget.onCode(decoded);
      }
    } catch (_) {
      // A single bad frame (detector hiccup, zero-sized draw) is not fatal;
      // the next tick tries again.
    } finally {
      _decoding = false;
    }
  }

  void _stopCamera() {
    _timer?.cancel();
    _timer = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    }
    _video.srcObject = null;
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return HtmlElementView(viewType: _viewType);
  }
}
