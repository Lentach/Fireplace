import 'dart:html' as html;

import 'package:http/http.dart' as http;

/// Downloads a file from [url] and triggers browser save with [filename].
/// Web-only implementation (blob + anchor download).
Future<void> downloadFile(String url, String filename) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('Download failed: ${response.statusCode}');
  }
  final blob = html.Blob([response.bodyBytes]);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = objectUrl
    ..download = _sanitizeFilename(filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Revoke after a short delay so the browser can start the download
  Future.delayed(const Duration(milliseconds: 500), () {
    html.Url.revokeObjectUrl(objectUrl);
  });
}

/// Trigger browser download of decrypted [bytes].
Future<void> saveBytesAsDownload(List<int> bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = objectUrl
    ..download = _sanitizeFilename(filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future.delayed(const Duration(milliseconds: 500), () {
    html.Url.revokeObjectUrl(objectUrl);
  });
}

String _sanitizeFilename(String name) {
  if (name.isEmpty) return 'document';
  final segments = name.replaceAll(RegExp(r'[/\\]'), ' ').split(RegExp(r'\s+'));
  String s = segments.last;
  if (s.isEmpty) s = 'document';
  return s.replaceAll(RegExp(r'[^\w\s.\-]'), '_');
}
