import 'dart:html' as html;
import 'dart:typed_data';

String? createAudioObjectUrl(Uint8List bytes) {
  final blob = html.Blob([bytes]);
  return html.Url.createObjectUrlFromBlob(blob);
}

void revokeAudioObjectUrl(String? url) {
  if (url != null && url.isNotEmpty) {
    html.Url.revokeObjectUrl(url);
  }
}
