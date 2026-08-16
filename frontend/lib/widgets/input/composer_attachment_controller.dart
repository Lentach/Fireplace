import 'package:flutter/foundation.dart';

import '../../services/media_crypto_service.dart';

/// What kind of media is staged in the composer.
enum StagedAttachmentKind { image, video }

/// One media item staged in the composer awaiting send (Clipboard Phase 2,
/// extended to video by the 0.1.12 media-picker redesign). Bytes stay in RAM
/// only — never written to disk (spec §3).
class StagedAttachment {
  const StagedAttachment({
    required this.bytes,
    required this.mimeType,
    required this.filename,
    this.kind = StagedAttachmentKind.image,
    this.durationSeconds,
  });

  final Uint8List bytes;
  final String mimeType;
  final String filename;
  final StagedAttachmentKind kind;

  /// Probed duration in seconds — video only, null when unknown (native
  /// picks: the picker's maxDuration is the cap there).
  final int? durationSeconds;
}

enum StageResult { ok, tooLarge, unsupportedType }

/// Image types accepted by paste (spec §3 v1 rules).
const kStageableImageMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
};

/// Video extensions accepted by the gallery/camera staging flow (client
/// policy — matches [MessagingProvider.sendVideoMessage]'s backstop).
const kStageableVideoExtensions = {'mp4', 'm4v', 'mov'};

/// Fallback filename for clipboard images that arrive without one
/// (Android commitContent, nameless web clipboard files).
String pastedFilenameForMime(String mimeType) {
  final ext = switch (mimeType) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => 'img',
  };
  return 'pasted.$ext';
}

/// Holds at most ONE staged item; a new [stage]/[stageVideo] replaces the
/// current one (v1 single-item rule). Validation happens at stage time so the
/// user gets feedback before tapping send (the async video duration probe is
/// the caller's job — it needs platform machinery this controller stays free
/// of).
class ComposerAttachmentController extends ChangeNotifier {
  StagedAttachment? _staged;

  StagedAttachment? get staged => _staged;

  StageResult stage({
    required Uint8List bytes,
    required String mimeType,
    required String filename,
  }) {
    if (!kStageableImageMimeTypes.contains(mimeType)) {
      return StageResult.unsupportedType;
    }
    if (bytes.length > MediaCryptoService.maxBytes) {
      return StageResult.tooLarge;
    }
    _staged = StagedAttachment(
      bytes: bytes,
      mimeType: mimeType,
      filename: filename,
    );
    notifyListeners();
    return StageResult.ok;
  }

  /// Stages a video picked from gallery/camera. Extension whitelist and size
  /// are checked here; the >60s duration check is the caller's (it needs the
  /// async web probe). [durationSeconds] is stored for the send envelope and
  /// the chip label.
  StageResult stageVideo({
    required Uint8List bytes,
    required String filename,
    int? durationSeconds,
  }) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    if (!kStageableVideoExtensions.contains(ext)) {
      return StageResult.unsupportedType;
    }
    if (bytes.length > MediaCryptoService.maxBytes) {
      return StageResult.tooLarge;
    }
    _staged = StagedAttachment(
      bytes: bytes,
      mimeType: ext == 'mov' ? 'video/quicktime' : 'video/mp4',
      filename: filename,
      kind: StagedAttachmentKind.video,
      durationSeconds: durationSeconds,
    );
    notifyListeners();
    return StageResult.ok;
  }

  void clear() {
    if (_staged == null) return;
    _staged = null;
    notifyListeners();
  }
}
