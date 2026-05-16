import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String? createAudioObjectUrl(Uint8List bytes) {
  final blob = web.Blob([bytes.toJS].toJS);
  return web.URL.createObjectURL(blob);
}

void revokeAudioObjectUrl(String? url) {
  if (url != null && url.isNotEmpty) {
    web.URL.revokeObjectURL(url);
  }
}
