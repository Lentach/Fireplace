import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Write decrypted video bytes to a temp file for [VideoPlayerController.file].
/// The caller owns the file and must delete it on dispose.
Future<String> writeVideoTempFile(Uint8List bytes, Object id) async {
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    'fp_video_${id}_${DateTime.now().microsecondsSinceEpoch}.mp4',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> deleteVideoTempFile(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Best-effort cleanup; the OS temp dir is reclaimable anyway.
  }
}

VideoPlayerController controllerForPath(String path) =>
    VideoPlayerController.file(File(path));
