import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Downloads a file from [url] and triggers browser save with [filename].
/// Web-only implementation (blob + anchor download).
Future<void> downloadFile(String url, String filename) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('Download failed: ${response.statusCode}');
  }
  await _saveBytesAsDownload(response.bodyBytes, filename);
}

/// Trigger browser download of decrypted [bytes].
Future<void> saveBytesAsDownload(List<int> bytes, String filename) async {
  await _saveBytesAsDownload(bytes, filename);
}

Future<void> _saveBytesAsDownload(List<int> bytes, String filename) async {
  final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final blob = web.Blob([u8.toJS].toJS);
  final objectUrl = web.URL.createObjectURL(blob);
  _triggerAnchorDownload(objectUrl, filename);
  Future.delayed(const Duration(milliseconds: 500), () {
    web.URL.revokeObjectURL(objectUrl);
  });
}

void _triggerAnchorDownload(String objectUrl, String filename) {
  final anchor = web.HTMLAnchorElement()
    ..href = objectUrl
    ..download = _sanitizeFilename(filename)
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}

String _sanitizeFilename(String name) {
  if (name.isEmpty) return 'document';
  final segments = name.replaceAll(RegExp(r'[/\\]'), ' ').split(RegExp(r'\s+'));
  String s = segments.last;
  if (s.isEmpty) s = 'document';
  return s.replaceAll(RegExp(r'[^\w\s.\-]'), '_');
}
