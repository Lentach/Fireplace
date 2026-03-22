import 'dart:html' as html;
import 'dart:typed_data';

String createGifObjectUrl(Uint8List bytes) {
  final blob = html.Blob([bytes], 'image/gif');
  return html.Url.createObjectUrlFromBlob(blob);
}

void revokeGifObjectUrl(String? url) {
  if (url != null && url.isNotEmpty) {
    html.Url.revokeObjectUrl(url);
  }
}
