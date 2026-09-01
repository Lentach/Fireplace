import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/encrypted_media_loader.dart';
import '../../utils/video_preview.dart';
import '../../utils/video_blob_url_stub.dart'
    if (dart.library.html) '../../utils/video_blob_url_web.dart' as video_blob;
import '../../utils/video_temp_file_stub.dart'
    if (dart.library.io) '../../utils/video_temp_file_io.dart' as video_temp;

/// Opens the fullscreen video player for [message].
///
/// Mirrors the image viewer's presentation (transparent full-bleed [Dialog],
/// tap-to-close chrome) so both media types dismiss identically. A dialog —
/// not a route — because that is the established pattern here and it gives
/// system-back dismissal for free.
Future<void> showVideoFullscreen(
  BuildContext context,
  MessageModel message,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => _VideoFullscreenView(message: message),
  );
}

/// Display aspect ratio of [value], honouring the container rotation that
/// [VideoPlayerValue.aspectRatio] silently drops.
double _rotationAwareAspectRatio(VideoPlayerValue value) {
  final size = value.size;
  if (size.width <= 0 || size.height <= 0) return 1.0;
  return videoRotationSwapsAxes(value.rotationCorrection)
      ? size.height / size.width
      : size.width / size.height;
}

/// Why the stage has no video to show.
///
/// Two cases, not three: [loadDecryptedMediaBytes] throws ONE undifferentiated
/// exception for fetch failure, oversize and decrypt failure alike, so this
/// screen cannot honestly name decryption as the cause of a load error.
enum _VideoStageError {
  /// The bubble is still optimistic — the blob has not finished uploading, so
  /// there is nothing to fetch yet. Not a failure; never say "failed" here.
  stillSending,

  /// Fetch, size guard, decrypt or codec initialisation failed. Which one is
  /// not knowable at this layer.
  unplayable,
}

/// Fullscreen player that owns the ONLY [VideoPlayerController] in the app.
///
/// The chat bubble is deliberately a static poster: a scrolling list must
/// never hold N live players or N decrypted multi-megabyte buffers, so the
/// fetch, the decrypt and the player all live here and die with the dialog.
class _VideoFullscreenView extends StatefulWidget {
  final MessageModel message;

  const _VideoFullscreenView({required this.message});

  @override
  State<_VideoFullscreenView> createState() => _VideoFullscreenViewState();
}

class _VideoFullscreenViewState extends State<_VideoFullscreenView> {
  VideoPlayerController? _controller;
  String? _objectUrl;
  String? _tempFilePath;
  bool _loading = true;
  _VideoStageError? _error;
  bool _playing = false;

  bool get _ready => _controller?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  void _teardown() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onControllerTick);
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

  void _onControllerTick() {
    final value = _controller?.value;
    if (value == null || !mounted) return;
    if (value.isPlaying != _playing) {
      setState(() => _playing = value.isPlaying);
    }
  }

  Future<void> _load() async {
    final url = widget.message.mediaUrl;
    // An optimistic bubble has no uploaded blob yet; nothing to fetch.
    if (url == null || url.isEmpty || !url.startsWith('http')) {
      setState(() {
        _loading = false;
        _error = _VideoStageError.stillSending;
      });
      return;
    }
    final token = context.read<AuthProvider>().token ?? '';
    try {
      final bytes = await loadDecryptedMediaBytes(
        url: url,
        token: token,
        key: widget.message.mediaKey,
        iv: widget.message.mediaIv,
      );
      if (!mounted) return;

      final VideoPlayerController controller;
      if (kIsWeb) {
        final blobUrl = video_blob.createVideoObjectUrl(bytes);
        _objectUrl = blobUrl;
        controller = VideoPlayerController.networkUrl(Uri.parse(blobUrl));
      } else {
        final path = await video_temp.writeVideoTempFile(
          bytes,
          widget.message.id,
        );
        if (!mounted) {
          // dispose() already ran with a null _tempFilePath; nothing else
          // will ever delete this file.
          video_temp.deleteVideoTempFile(path).ignore();
          return;
        }
        _tempFilePath = path;
        controller = video_temp.controllerForPath(path);
      }
      // Assign before initialize() so a dispose during the await still tears
      // the controller down.
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      controller.addListener(_onControllerTick);
      setState(() {
        _loading = false;
        _playing = true;
      });
      await controller.setLooping(false);
      await controller.play();
    } catch (_) {
      if (!mounted) return;
      _teardown();
      setState(() {
        _loading = false;
        _error = _VideoStageError.unplayable;
      });
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
      return;
    }
    if (controller.value.position >= controller.value.duration) {
      controller.seekTo(Duration.zero);
    }
    controller.play();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(child: _buildStage()),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        key: const ValueKey('video_fullscreen_close'),
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_ready)
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    padding: EdgeInsets.zero,
                    colors: VideoProgressColors(
                      playedColor: Theme.of(context).colorScheme.primary,
                      // Same media-scrim precedent as the bubble's time chip:
                      // a scrim over arbitrary frames is theme-independent.
                      bufferedColor: Colors.white.withValues(alpha: 0.35),
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStage() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    final error = _error;
    if (error != null || !_ready) {
      // One error surface, not two: the glyph and its explanation belong in
      // the same branch. This used to render `videoMessage` — the bubble's
      // LABEL ("Video") — which told the user nothing.
      final stillSending = error == _VideoStageError.stillSending;
      final l10n = AppLocalizations.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              stillSending ? Icons.cloud_upload_outlined : Icons.broken_image,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 12),
            Text(
              stillSending ? l10n.videoStillSending : l10n.videoFailedToLoad,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    final controller = _controller!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayback,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              // NOT controller.value.aspectRatio: that getter ignores
              // rotationCorrection, while VideoPlayer compensates internally
              // with a RotatedBox. Trusting it squashes every rotated phone
              // recording into a landscape box.
              aspectRatio: _rotationAwareAspectRatio(controller.value),
              child: VideoPlayer(controller),
            ),
          ),
          if (!_playing)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                size: 84,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }
}
