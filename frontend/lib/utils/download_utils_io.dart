import 'dart:io' show File;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Downloads a file from [url] and saves it to app documents with [filename].
/// Native (iOS/Android/desktop) implementation.
Future<void> downloadFile(String url, String filename) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('Download failed: ${response.statusCode}');
  }
  final dir = await getApplicationDocumentsDirectory();
  final safe = _sanitizeFilename(filename);
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(response.bodyBytes);
}

/// Save raw [bytes] as a user-visible download (app documents on native).
Future<void> saveBytesAsDownload(List<int> bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final safe = _sanitizeFilename(filename);
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes);
}

String _sanitizeFilename(String name) {
  if (name.isEmpty) return 'document';
  final segments = name.replaceAll(RegExp(r'[/\\]'), ' ').split(RegExp(r'\s+'));
  String s = segments.last;
  if (s.isEmpty) s = 'document';
  return s.replaceAll(RegExp(r'[^\w\s.\-]'), '_');
}
