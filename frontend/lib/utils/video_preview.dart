import 'dart:typed_data';

/// Video container extensions the client will send.
///
/// Lives here rather than in the composer's staging model because a picked
/// video no longer stages — it sends immediately. Duplicated deliberately
/// against `ChatActionTiles`' routing whitelist: routing decides which branch
/// a pick takes, this one is the last gate before an IMMEDIATE, unconfirmed
/// send. Keep the two in step.
const kSendableVideoExtensions = {'mp4', 'm4v', 'mov'};

/// Container MIME for a sendable video filename. `.mov` is QuickTime, not
/// MP4 — Safari consults the blob type before sniffing, so the web probe
/// labels the blob with this instead of a blanket `video/mp4`.
String videoMimeForFilename(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  return switch (ext) {
    'mov' => 'video/quicktime',
    'm4v' => 'video/x-m4v',
    _ => 'video/mp4',
  };
}

/// True when a container rotation turns the frame a quarter turn, swapping the
/// meaning of the coded width and height.
///
/// Load-bearing on Android. `video_player` reports `value.size` as the CODED
/// size and `value.rotationCorrection` separately; its own `aspectRatio`
/// getter IGNORES rotation, and the `VideoPlayer` widget compensates by
/// wrapping its child in `RotatedBox(quarterTurns: rotation ~/ 90)`. A phone
/// portrait recording therefore arrives as 1920x1080 with a 90 degree
/// correction, and any consumer that trusts `size` or `aspectRatio` verbatim
/// renders a portrait clip as landscape.
///
/// Web needs no such correction: `HTMLVideoElement.videoWidth`/`videoHeight`
/// are already display dimensions.
bool videoRotationSwapsAxes(int rotationDegrees) {
  final normalized = ((rotationDegrees % 360) + 360) % 360;
  return normalized == 90 || normalized == 270;
}

/// What a picked video's container can tell us before it is encrypted and
/// sent: playback length plus the intrinsic geometry and a compact
/// placeholder for the chat bubble.
///
/// Every field is nullable because probing is best-effort and platform
/// dependent — an unparseable container, a codec the platform cannot open, or
/// a host with no video plugin all answer "unknown" rather than failing the
/// send. Callers treat unknown geometry as "fall back to the legacy fixed
/// frame" and unknown duration as "cannot enforce the duration cap here".
class VideoPreview {
  /// Container duration in seconds; null when the platform cannot read it.
  final double? durationSeconds;

  /// Intrinsic pixel geometry. Both are set together or both are null —
  /// a lone dimension cannot produce an aspect ratio.
  final int? width;
  final int? height;

  /// Base64 ThumbHash of a real frame. Web-only for now: extracting a frame
  /// needs a decode surface, which the native probe does not have.
  final String? thumbHash;

  const VideoPreview({
    this.durationSeconds,
    this.width,
    this.height,
    this.thumbHash,
  });

  /// Nothing could be read. Distinct from a partially-probed preview so
  /// callers can log the difference.
  static const unknown = VideoPreview();

  /// True when [width] and [height] form a usable aspect ratio.
  bool get hasGeometry =>
      width != null && height != null && width! > 0 && height! > 0;

  /// Duration rounded to whole seconds for the wire envelope, which carries
  /// `mediaDuration` as an int.
  int? get durationInSeconds {
    final value = durationSeconds;
    if (value == null || !value.isFinite || value <= 0) return null;
    return value.round();
  }
}

/// Probe a picked video's duration, geometry and poster frame.
///
/// Declared here so both platform implementations share one signature; the
/// conditional import in the composer picks the real one.
typedef VideoPreviewProbe = Future<VideoPreview> Function(Uint8List bytes);
