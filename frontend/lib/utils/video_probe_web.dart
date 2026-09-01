import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'media_preview_metadata.dart';
import 'video_preview.dart';

/// Longest we will wait for the browser to parse a container. An unparseable
/// file may fire neither `loadedmetadata` nor `error`.
const _kMetadataTimeout = Duration(seconds: 5);

/// Longest we will wait for a seek to land on a decodable frame. Failing this
/// costs only the ThumbHash — geometry and duration are already in hand.
const _kPosterTimeout = Duration(seconds: 5);

/// Longest side of the poster we rasterise. [MediaPreviewMetadata] re-decodes
/// at <=100 px anyway, so anything larger is wasted encode time.
const _kPosterMaxSide = 240;

/// Read duration, intrinsic geometry and a real poster frame from a picked
/// video by loading it into a detached `<video>` through a temporary blob URL.
///
/// Two phases, degrading independently: `loadedmetadata` yields duration and
/// `videoWidth`/`videoHeight`, then a seek + canvas draw yields a frame we
/// ThumbHash. A failure in phase two still returns phase one's data, because
/// geometry alone is what fixes the chat bubble's aspect ratio.
///
/// The blob is same-origin, so the canvas is never tainted and `toDataURL`
/// cannot throw a security error.
Future<VideoPreview> probeVideoPreview(Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'video/mp4'),
  );
  final url = web.URL.createObjectURL(blob);
  // preload='auto' (not 'metadata'): we need a decodable frame, and Safari
  // will not produce one from a metadata-only load.
  final video = web.HTMLVideoElement()
    ..preload = 'auto'
    ..muted = true;
  video.setAttribute('playsinline', 'true');

  try {
    video.src = url;
    if (!await _awaitMetadata(video)) return VideoPreview.unknown;

    final rawDuration = video.duration;
    final duration = rawDuration.isFinite && rawDuration > 0
        ? rawDuration
        : null;
    final width = video.videoWidth;
    final height = video.videoHeight;
    final hasGeometry = width > 0 && height > 0;

    String? thumbHash;
    if (hasGeometry) {
      thumbHash = await _capturePosterThumbHash(
        video,
        width: width,
        height: height,
        durationSeconds: duration,
      );
    }

    return VideoPreview(
      durationSeconds: duration,
      width: hasGeometry ? width : null,
      height: hasGeometry ? height : null,
      thumbHash: thumbHash,
    );
  } catch (_) {
    return VideoPreview.unknown;
  } finally {
    // Drop the decoder before revoking, or Safari keeps the blob alive.
    video.removeAttribute('src');
    video.load();
    web.URL.revokeObjectURL(url);
  }
}

/// Completes true on `loadedmetadata`, false on `error` or timeout.
Future<bool> _awaitMetadata(web.HTMLVideoElement video) {
  final completer = Completer<bool>();
  late final JSFunction onLoaded;
  late final JSFunction onError;

  void finish(bool value) {
    if (completer.isCompleted) return;
    video.removeEventListener('loadedmetadata', onLoaded);
    video.removeEventListener('error', onError);
    completer.complete(value);
  }

  onLoaded = ((web.Event _) => finish(true)).toJS;
  onError = ((web.Event _) => finish(false)).toJS;
  video.addEventListener('loadedmetadata', onLoaded);
  video.addEventListener('error', onError);
  Timer(_kMetadataTimeout, () => finish(false));
  return completer.future;
}

/// Seeks slightly into the clip, rasterises that frame to a canvas and returns
/// its ThumbHash. Null on any failure — the caller keeps the geometry.
///
/// The seek target is deliberately not 0: cameras routinely open on a black or
/// half-exposed frame, which would ThumbHash to a featureless grey smear.
Future<String?> _capturePosterThumbHash(
  web.HTMLVideoElement video, {
  required int width,
  required int height,
  required double? durationSeconds,
}) async {
  try {
    if (durationSeconds != null) {
      final target = math.min(durationSeconds * 0.1, 1.0);
      if (target > 0) {
        video.currentTime = target;
        if (!await _awaitSeek(video)) return null;
      }
    }

    final scale = math.min(1.0, _kPosterMaxSide / math.max(width, height));
    final targetWidth = math.max(1, (width * scale).round());
    final targetHeight = math.max(1, (height * scale).round());

    final canvas = web.HTMLCanvasElement()
      ..width = targetWidth
      ..height = targetHeight;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) return null;
    context.drawImage(video, 0, 0, targetWidth, targetHeight);

    // JPEG, not PNG: the ThumbHash only needs coarse colour, and a PNG of a
    // photographic frame is an order of magnitude larger to encode.
    final dataUrl = canvas.toDataURL('image/jpeg', 0.7.toJS);
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    final posterBytes = base64Decode(dataUrl.substring(comma + 1));

    final metadata = await MediaPreviewMetadata.fromEncodedBytes(posterBytes);
    return metadata?.thumbHash;
  } catch (_) {
    return null;
  }
}

/// Completes true on `seeked`, false on `error` or timeout.
Future<bool> _awaitSeek(web.HTMLVideoElement video) {
  final completer = Completer<bool>();
  late final JSFunction onSeeked;
  late final JSFunction onError;

  void finish(bool value) {
    if (completer.isCompleted) return;
    video.removeEventListener('seeked', onSeeked);
    video.removeEventListener('error', onError);
    completer.complete(value);
  }

  onSeeked = ((web.Event _) => finish(true)).toJS;
  onError = ((web.Event _) => finish(false)).toJS;
  video.addEventListener('seeked', onSeeked);
  video.addEventListener('error', onError);
  Timer(_kPosterTimeout, () => finish(false));
  return completer.future;
}
