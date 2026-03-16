// Stub for web: file deletion and file read are not applicable (web uses blob).

Future<void> deleteFileIfExists(String path) async {
  // No-op on web
}

Future<List<int>> readFileBytes(String path) async {
  throw UnsupportedError('readFileBytes not available on web');
}
