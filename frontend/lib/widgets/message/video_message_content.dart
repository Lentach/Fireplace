import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/encrypted_media_loader.dart';
import '../../utils/video_blob_url_stub.dart'
    if (dart.library.html) '../../utils/video_blob_url_web.dart' as video_blob;
import '../../utils/video_temp_file_stub.dart'
    if (dart.library.io) '../../utils/video_temp_file_io.dart' as video_temp;
import 'media_preview_frame.dart';

/// Video message: poster placeholder first, full fetch + decrypt + player
/// init ONLY on tap — a list must never hold N live video players (or N
/// decrypted 20 MB buffers).
///
/// Web wraps the decrypted bytes in a blob object URL (same pattern as
/// [GifMessageContent], revoked on dispose); native writes them to a temp
/// file for [VideoPlayerController.file] and deletes it on dispose.
/// Message content is a motion-banned zone: no entrance animation.
class VideoMessageContent extends StatefulWidget {
  final MessageModel message;

  const VideoMessageContent({super.key, required this.message});

  @override
  State<VideoMessageContent> createState() => _VideoMessageContentState();
}

class _VideoMessageContentState extends State<VideoMessageContent> {
  VideoPlayerController? _controller;
  String? _objectUrl;
  String? _tempFilePath;
  bool _loading = false;
  bool _error = false;
  bool _playing = false;

  bool get _ready => _controller?.value.isInitialized ?? false;

  @override
  void didUpdateWidget(VideoMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl ||
        oldWidget.message.mediaKey != widget.message.mediaKey ||
        oldWidget.message.mediaIv != widget.message.mediaIv) {
      _teardown();
      setState(() {
        _loading = false;
        _error = false;
        _playing = false;
      });
    }
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  void _teardown() {
    _controller?.removeListener(_onControllerTick);
    _controller?.dispose();
    _controller = null;
    if (_objectUrl != null) {
      video_blob.revokeVideoObjectUrl(_objectUrl);
      _objectUrl = null;
    }
    final tmp = _tempFilePath;
    _tempFilePath = null;
    if (tmp != null) {
      video_temp.deleteVideoTempFile(tmp).ignore();
    }
  }

  void _onControllerTick() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing != _playing && mounted) {
      setState(() => _playing = playing);
    }
  }

  Future<void> _initAndPlay() async {
    if (_loading) return;
    final url = widget.message.mediaUrl;
    // Optimistic bubbles have no uploaded blob yet; a missing/local URL means
    // there is nothing to fetch.
    if (url == null || url.isEmpty || !url.startsWith('http')) {
      setState(() => _error = true);
      return;
    }
    final token = context.read<AuthProvider>().token ?? '';
    setState(() {
      _loading = true;
      _error = false;
    });
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
      // Set before initialize() so dispose() during the await still tears
      // the controller down.
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      controller.addListener(_onControllerTick);
      setState(() => _loading = false);
      await controller.play();
    } catch (_) {
      if (!mounted) return;
      _teardown();
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _onTap() {
    if (_loading) return;
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          controller.seekTo(Duration.zero);
        }
        controller.play();
      }
      return;
    }
    _initAndPlay();
  }

  String? _durationLabel() {
    Duration? duration;
    final value = _controller?.value;
    if (value != null && value.isInitialized && value.duration > Duration.zero) {
      duration = value.duration;
    } else {
      final seconds = widget.message.mediaDuration;
      if (seconds != null && seconds > 0) duration = Duration(seconds: seconds);
    }
    if (duration == null) return null;
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return Semantics(
      label: AppLocalizations.of(context).videoMessage,
      button: true,
      child: MediaPreviewFrame(
        mediaWidth: message.mediaWidth,
        mediaHeight: message.mediaHeight,
        mediaThumbHash: message.mediaThumbHash,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: _ready ? _buildPlayer(context) : _buildPoster(context),
        ),
      ),
    );
  }

  Widget _buildPlayer(BuildContext context) {
    final controller = _controller!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        if (!_playing) const Center(child: _PlayBadge()),
        Positioned(
          left: 8,
          right: 8,
          bottom: 4,
          child: VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: EdgeInsets.zero,
            colors: VideoProgressColors(
              playedColor: Theme.of(context).colorScheme.primary,
              // Same media-scrim precedent as the bubble's time overlay: a
              // scrim over arbitrary video frames is theme-independent.
              bufferedColor: Colors.white.withValues(alpha: 0.35),
              backgroundColor: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
        _durationChip(top: true),
      ],
    );
  }

  Widget _buildPoster(BuildContext context) {
    final Widget center;
    if (_loading) {
      center = const CircularProgressIndicator(strokeWidth: 2);
    } else if (_error) {
      center = const Icon(Icons.broken_image, size: 48);
    } else {
      center = const _PlayBadge();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // MediaPreviewFrame already paints the thumbhash placeholder behind
        // this stack; the poster only adds the affordance on top.
        Center(child: center),
        _durationChip(top: false),
      ],
    );
  }

  /// Small duration pill; sits top-left on the live player (the progress bar
  /// owns the bottom edge) and bottom-left on the poster (the bubble's time
  /// overlay owns the bottom-right corner).
  Widget _durationChip({required bool top}) {
    final label = _durationLabel();
    if (label == null) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      top: top ? 8 : null,
      bottom: top ? null : 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

/// Static play affordance over the media frame — scrim + glyph, same
/// theme-independent overlay treatment as the bubble's media time chip.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        size: 36,
        color: Colors.white.withValues(alpha: 0.9),
      ),
    );
  }
}
