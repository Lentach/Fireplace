import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'video_preview.dart';
import 'video_temp_file_io.dart';

/// Longest we will wait for the platform video plugin to open the file.
const _kProbeTimeout = Duration(seconds: 10);

/// Read duration and intrinsic geometry from a picked video by opening it with
/// the platform video plugin.
///
/// [VideoPlayerController] needs a file, not bytes, so the clip is written to
/// the temp dir and removed again — the same helper the fullscreen player uses.
///
/// No ThumbHash: extracting a frame needs a decode surface the plugin does not
/// expose. Geometry alone is what fixes the bubble's aspect ratio, so the
/// receiving side degrades to a plain frame rather than a blurred one.
///
/// Rotation is applied via [videoRotationSwapsAxes]: `value.size` is the CODED
/// size, so a phone portrait recording reads 1920x1080 until the 90 degree
/// correction is folded in. Publishing the raw size would render every
/// portrait clip as landscape on the receiving side.
///
/// Answers [VideoPreview.unknown] on any failure, including hosts with no
/// video plugin registered at all (desktop, the widget-test binding) — probing
/// is best-effort and must never block a send.
Future<VideoPreview> probeVideoPreview(Uint8List bytes) async {
  String? path;
  VideoPlayerController? controller;
  try {
    path = await writeVideoTempFile(bytes, 'probe');
    controller = controllerForPath(path);
    await controller.initialize().timeout(_kProbeTimeout);

    final value = controller.value;
    final size = value.size;
    final swap = videoRotationSwapsAxes(value.rotationCorrection);
    final width = (swap ? size.height : size.width).round();
    final height = (swap ? size.width : size.height).round();
    final hasGeometry = width > 0 && height > 0;
    final durationSeconds = value.duration > Duration.zero
        ? value.duration.inMilliseconds / 1000.0
        : null;

    return VideoPreview(
      durationSeconds: durationSeconds,
      width: hasGeometry ? width : null,
      height: hasGeometry ? height : null,
    );
  } catch (_) {
    return VideoPreview.unknown;
  } finally {
    // Dispose before deleting: the plugin may still hold the file open.
    await controller?.dispose();
    await deleteVideoTempFile(path);
  }
}
