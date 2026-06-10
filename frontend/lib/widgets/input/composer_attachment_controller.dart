import 'package:flutter/foundation.dart';

import '../../services/media_crypto_service.dart';

/// One image staged in the composer awaiting send (Clipboard Phase 2).
/// Bytes stay in RAM only — never written to disk (spec §3).
class StagedAttachment {
  const StagedAttachment({
    required this.bytes,
    required this.mimeType,
    required this.filename,
  });

  final Uint8List bytes;
  final String mimeType;
  final String filename;
}

enum StageResult { ok, tooLarge, unsupportedType }

/// Image types accepted by paste (spec §3 v1 rules).
const kStageableImageMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
};

/// Holds at most ONE staged image; a new [stage] replaces the current one
/// (v1 single-image rule). Validation happens at stage time so the user gets
/// feedback before tapping send.
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

  void clear() {
    if (_staged == null) return;
    _staged = null;
    notifyListeners();
  }
}
