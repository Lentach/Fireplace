import 'dart:io' show File;

/// Deletes a file if it exists. Used on native platforms for temp voice recordings.
Future<void> deleteFileIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

/// Reads file bytes from path. Used when file_picker returns path but not bytes (e.g. large files).
Future<List<int>> readFileBytes(String path) async {
  final file = File(path);
  return await file.readAsBytes();
}
