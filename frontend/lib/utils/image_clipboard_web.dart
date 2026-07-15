import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get canCopyImageToClipboard => true;

/// Writes [bytes] to the browser clipboard via the Async Clipboard API.
/// Browsers only reliably accept `image/png` for clipboard writes, so a
/// non-PNG image is re-encoded to PNG through a canvas first.
Future<void> copyImageToClipboard(Uint8List bytes, String mimeType) async {
  final mime = mimeType.isEmpty ? 'image/png' : mimeType;
  final web.Blob pngBlob = mime == 'image/png'
      ? web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'))
      : await _reencodeToPng(bytes, mime);

  final items = <String, web.Blob>{'image/png': pngBlob};
  final item = web.ClipboardItem(items.jsify() as JSObject);
  await web.window.navigator.clipboard.write([item].toJS).toDart;
}

Future<web.Blob> _reencodeToPng(Uint8List bytes, String mime) async {
  final srcBlob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(srcBlob);
  try {
    final img = web.HTMLImageElement();
    img.src = url;
    await img.decode().toDart;
    final canvas = web.HTMLCanvasElement()
      ..width = img.naturalWidth
      ..height = img.naturalHeight;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.drawImage(img, 0, 0);

    final completer = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => completer.complete(b)).toJS, 'image/png');
    final blob = await completer.future;
    if (blob == null) throw StateError('Canvas toBlob returned null');
    return blob;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
