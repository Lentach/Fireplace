import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'audio_mime.dart';

String? createAudioObjectUrl(Uint8List bytes) {
  // Stamp the detected MIME type on the blob. Without it, mobile Safari / mobile
  // Chrome refuse to play the object URL (MediaError code 4); desktop Chrome
  // sniffs a typeless blob and works, which is why this only bit on phones.
  final mime = detectAudioMimeType(bytes);
  final web.Blob blob = mime != null
      ? web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime))
      : web.Blob([bytes.toJS].toJS);
  return web.URL.createObjectURL(blob);
}

void revokeAudioObjectUrl(String? url) {
  if (url != null && url.isNotEmpty) {
    web.URL.revokeObjectURL(url);
  }
}
