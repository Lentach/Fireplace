import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'media_preview_metadata.dart';
import 'video_preview.dart';

/// Longest we will wait for the browser to parse a container. An unparseable
/// file may fire neither `loadedmetadata` nor `error`.
const _kMetadataTimeout = Duration(seconds: 5);

/// Longest we will wait for intrinsic dimensions AFTER `loadedmetadata`.
///
/// WebKit fires `loadedmetadata` with `videoWidth`/`videoHeight` still 0 for
/// some QuickTime camera recordings and only reports real dimensions on the
/// later `resize` / `loadeddata` events. Reading geometry at `loadedmetadata`
/// alone published three of four iPhone-recorded clips WITHOUT geometry —
/// the receiving bubble then fell back to its 220 px legacy frame and showed
/// a grey square with no poster (owner report 2026-09-05).
const _kGeometryTimeout = Duration(seconds: 3);

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
/// [mimeType] labels the blob. Safari consults the type before sniffing, so a
/// `.mov` capture labelled `video/mp4` is a needless gamble; the caller
/// derives it from the picked filename ([videoMimeForFilename]).
///
/// The blob is same-origin, so the canvas is never tainted and `toDataURL`
/// cannot throw a security error.
Future<VideoPreview> probeVideoPreview(
  Uint8List bytes, {
  String mimeType = 'video/mp4',
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
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

    var width = video.videoWidth;
    var height = video.videoHeight;
    if (width <= 0 || height <= 0) {
      await _awaitGeometry(video);
      width = video.videoWidth;
      height = video.videoHeight;
    }
    final hasGeometry = width > 0 && height > 0;
    // Read AFTER the geometry wait: on the same WebKit path that reports 0x0
    // at loadedmetadata the duration is often NaN there too, and losing it
    // silently disables the composer's duration cap.
    final rawDuration = video.duration;
    final duration = rawDuration.isFinite && rawDuration > 0
        ? rawDuration
        : null;

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

/// Completes when the element reports non-zero dimensions, on `error`, or on
/// timeout. `resize` is the event WebKit fires when the dimensions become
/// known; `loadeddata` / `canplay` cover engines that never fire it.
Future<void> _awaitGeometry(web.HTMLVideoElement video) {
  final completer = Completer<void>();
  late final JSFunction onEvent;
  const events = ['resize', 'loadeddata', 'canplay', 'error'];

  void finish() {
    if (completer.isCompleted) return;
    for (final name in events) {
      video.removeEventListener(name, onEvent);
    }
    completer.complete();
  }

  onEvent = ((web.Event event) {
    if (event.type == 'error' || video.videoWidth > 0) finish();
  }).toJS;
  for (final name in events) {
    video.addEventListener(name, onEvent);
  }
  Timer(_kGeometryTimeout, finish);
  return completer.future;
}

/// Seeks slightly into the clip, rasterises that frame to a canvas and returns
/// its ThumbHash. Null on any failure — the caller keeps the geometry.
///
/// The seek target is deliberately not 0: cameras routinely open on a black or
/// half-exposed frame, which would ThumbHash to a featureless grey smear.
///
/// iOS Safari needs more than a seek. It fires `seeked` once the playhead
/// moves, which is NOT a promise that a frame has been decoded, and it will
/// not decode at all for a `<video>` that has never played — so `drawImage`
/// lands on an empty canvas and the bubble shows a blank poster. The fix is to
/// nudge playback (muted + playsinline, already set) to force a decode, then
/// wait for a REAL presented frame via `requestVideoFrameCallback` where it
/// exists. Both steps degrade to the old behaviour elsewhere.
Future<String?> _capturePosterThumbHash(
  web.HTMLVideoElement video, {
  required int width,
  required int height,
  required double? durationSeconds,
}) async {
  try {
    await _forceDecode(video);

    if (durationSeconds != null) {
      final target = math.min(durationSeconds * 0.1, 1.0);
      if (target > 0) {
        video.currentTime = target;
        if (!await _awaitSeek(video)) return null;
      }
    }
    await _awaitPresentedFrame(video);

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
  } finally {
    video.pause();
  }
}

/// Nudges muted playback so the decoder produces at least one frame.
///
/// iOS will not decode for a `<video>` that has never played. `play()` can
/// reject (autoplay policy) — that is fine and non-fatal, since desktop
/// browsers decode on seek alone.
Future<void> _forceDecode(web.HTMLVideoElement video) async {
  try {
    await video.play().toDart;
  } catch (_) {
    // Autoplay refused; the seek path may still yield a frame.
  }
}

/// Resolves once the compositor has actually presented a frame.
///
/// Uses `requestVideoFrameCallback` when the browser has it (Safari 15.4+,
/// Chrome 83+); otherwise yields briefly, which is what the code did before.
Future<void> _awaitPresentedFrame(web.HTMLVideoElement video) {
  final completer = Completer<void>();
  void finish() {
    if (!completer.isCompleted) completer.complete();
  }

  final target = video as JSObject;
  final hasCallback = target
      .hasProperty('requestVideoFrameCallback'.toJS)
      .toDart;
  if (hasCallback) {
    target.callMethod(
      'requestVideoFrameCallback'.toJS,
      ((JSAny _, JSAny _) => finish()).toJS,
    );
  }
  // Backstop: a paused/exhausted decoder may never present another frame.
  Timer(const Duration(milliseconds: 320), finish);
  return completer.future;
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
