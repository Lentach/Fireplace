import 'dart:io' show File;

/// Deletes a file if it exists. Used on native platforms for temp voice recordings.

Future<void> deleteFileIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
