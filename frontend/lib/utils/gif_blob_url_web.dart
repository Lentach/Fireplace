import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String createGifObjectUrl(Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/gif'),
  );
  return web.URL.createObjectURL(blob);
}

void revokeGifObjectUrl(String? url) {
  if (url != null && url.isNotEmpty) {
    web.URL.revokeObjectURL(url);
  }
}
