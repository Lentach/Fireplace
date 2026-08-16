import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Read the duration (seconds) of a picked video by loading its metadata into
/// a detached `<video>` element via a temporary blob URL. Cheap: `preload =
/// 'metadata'` never decodes frames. Returns null when the browser cannot
/// parse the container (caller treats that as "duration unknown").
Future<double?> probeVideoDurationSeconds(Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'video/mp4'),
  );
  final url = web.URL.createObjectURL(blob);
  final video = web.HTMLVideoElement()..preload = 'metadata';
  final completer = Completer<double?>();

  void finish(double? value) {
    if (completer.isCompleted) return;
    video.removeAttribute('src');
    web.URL.revokeObjectURL(url);
    completer.complete(value);
  }

  video.addEventListener(
    'loadedmetadata',
    ((web.Event _) {
      final d = video.duration;
      finish(d.isFinite && d > 0 ? d : null);
    }).toJS,
  );
  video.addEventListener('error', ((web.Event _) => finish(null)).toJS);
  video.src = url;
  // Bounded: an unparseable container may fire neither event.
  Timer(const Duration(seconds: 5), () => finish(null));
  return completer.future;
}
