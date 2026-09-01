import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';

import '../../models/message_model.dart';
import '../../utils/encrypted_media_loader.dart';
import '../../utils/video_blob_url_stub.dart'
    if (dart.library.html) '../../utils/video_blob_url_web.dart' as video_blob;
import '../../utils/video_temp_file_stub.dart'
    if (dart.library.io) '../../utils/video_temp_file_io.dart' as video_temp;

/// Why a video has nothing to show.
///
/// Two cases, not three: [loadDecryptedMediaBytes] throws ONE undifferentiated
/// exception for fetch failure, oversize and decrypt failure alike, so no
/// caller can honestly name decryption as the cause of a load error.
enum VideoStageError {
  /// The bubble is still optimistic — the blob has not finished uploading, so
  /// there is nothing to fetch yet. Not a failure; never say "failed" here.
  stillSending,

  /// Fetch, size guard, decrypt or codec initialisation failed. Which one is
  /// not knowable at this layer.
  unplayable,
}

/// Owns ONE decrypted video and the platform resources behind it.
///
/// Shared by the in-bubble tile player and the fullscreen viewer so the two can
/// never drift apart on cleanup: web holds an object URL, native holds a temp
/// file, and BOTH leak without a matching teardown. Callers own the lifecycle —
/// construct, [load], then [dispose] exactly once.
class VideoPlaybackSession {
  final MessageModel message;
  final String token;

  VideoPlayerController? _controller;
  String? _objectUrl;
  String? _tempFilePath;
  bool _disposed = false;

  VideoPlaybackSession({required this.message, required this.token});

  VideoPlayerController? get controller => _controller;

  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Fetches, decrypts and initialises the player.
  ///
  /// Returns null on success, or the reason there is nothing to play. Safe to
  /// race against [dispose]: a session disposed mid-await tears down whatever
  /// it had already acquired and reports [VideoStageError.unplayable] to a
  /// caller that is, by then, gone.
  Future<VideoStageError?> load() async {
    final url = message.mediaUrl;
    // An optimistic bubble has no uploaded blob yet; nothing to fetch.
    if (url == null || url.isEmpty || !url.startsWith('http')) {
      return VideoStageError.stillSending;
    }
    try {
      final bytes = await loadDecryptedMediaBytes(
        url: url,
        token: token,
        key: message.mediaKey,
        iv: message.mediaIv,
      );
      if (_disposed) return VideoStageError.unplayable;

      final VideoPlayerController controller;
      if (kIsWeb) {
        final blobUrl = video_blob.createVideoObjectUrl(bytes);
        _objectUrl = blobUrl;
        controller = VideoPlayerController.networkUrl(Uri.parse(blobUrl));
      } else {
        final path = await video_temp.writeVideoTempFile(bytes, message.id);
        if (_disposed) {
          // dispose() already ran with a null _tempFilePath; nothing else
          // would ever delete this file.
          video_temp.deleteVideoTempFile(path).ignore();
          return VideoStageError.unplayable;
        }
        _tempFilePath = path;
        controller = video_temp.controllerForPath(path);
      }
      // Assign before initialize() so a dispose during the await still tears
      // the controller down.
      _controller = controller;
      await controller.initialize();
      if (_disposed) return VideoStageError.unplayable;
      return null;
    } catch (_) {
      _releaseResources();
      return VideoStageError.unplayable;
    }
  }

  void dispose() {
    _disposed = true;
    _releaseResources();
  }

  void _releaseResources() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    if (_objectUrl != null) {
      video_blob.revokeVideoObjectUrl(_objectUrl);
      _objectUrl = null;
    }
    if (_tempFilePath != null) {
      video_temp.deleteVideoTempFile(_tempFilePath).ignore();
      _tempFilePath = null;
    }
  }
}
