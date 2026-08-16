import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String createVideoObjectUrl(Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'video/mp4'),
  );
  return web.URL.createObjectURL(blob);
}

void revokeVideoObjectUrl(String? url) {
  if (url != null && url.isNotEmpty) {
    web.URL.revokeObjectURL(url);
  }
}
