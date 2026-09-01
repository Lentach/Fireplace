import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import 'media_preview_frame.dart';
import 'video_fullscreen_view.dart';
import 'video_playback_session.dart';

/// Video message bubble: a poster that plays IN PLACE on tap, and opens
/// [showVideoFullscreen] on double tap.
///
/// Playback is tap-initiated, never automatic. Autoplaying every video in view
/// would fetch and decrypt a multi-megabyte buffer per bubble just for
/// scrolling past it; only a video the user actually asks for gets a
/// [VideoPlayerController], and it is released the moment the bubble leaves
/// the list (a lazy list disposes its off-screen children).
///
/// The frame's aspect ratio comes from `mediaWidth`/`mediaHeight` in the E2E
/// envelope, written at send time by the composer's `probeVideoPreview` pass.
/// Messages sent before that existed carry neither and fall back to
/// [MediaPreviewFrame.legacyHeight] — upgrade-only, never a regression.
///
/// Message content is a motion-banned zone: no entrance animation.
class VideoMessageContent extends StatefulWidget {
  final MessageModel message;

  const VideoMessageContent({super.key, required this.message});

  @override
  State<VideoMessageContent> createState() => _VideoMessageContentState();
}

class _VideoMessageContentState extends State<VideoMessageContent> {
  VideoPlaybackSession? _session;
  VideoStageError? _error;
  bool _loading = false;
  bool _playing = false;

  bool get _ready => _session?.isReady ?? false;

  @override
  void dispose() {
    _session?.controller?.removeListener(_onTick);
    _session?.dispose();
    super.dispose();
  }

  void _onTick() {
    final value = _session?.controller?.value;
    if (value == null || !mounted) return;
    if (value.isPlaying != _playing) {
      setState(() => _playing = value.isPlaying);
    }
  }

  /// `m:ss` from the envelope's `mediaDuration`. Null when the sending
  /// platform could not read the container's duration.
  String? _durationLabel() {
    final seconds = widget.message.mediaDuration;
    if (seconds == null || seconds <= 0) return null;
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final remainder = duration.inSeconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  Future<void> _handleTap() async {
    final session = _session;
    if (session != null && session.isReady) {
      final controller = session.controller!;
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
      return;
    }
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final next = VideoPlaybackSession(
      message: widget.message,
      token: context.read<AuthProvider>().token ?? '',
    );
    _session = next;
    final failure = await next.load();
    if (!mounted) {
      next.dispose();
      return;
    }
    if (failure != null) {
      setState(() {
        _loading = false;
        _error = failure;
      });
      return;
    }
    next.controller!.addListener(_onTick);
    setState(() {
      _loading = false;
      _playing = true;
    });
    await next.controller!.setLooping(false);
    await next.controller!.play();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).videoMessage,
      button: true,
      child: MediaPreviewFrame(
        mediaWidth: widget.message.mediaWidth,
        mediaHeight: widget.message.mediaHeight,
        mediaThumbHash: widget.message.mediaThumbHash,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          // Kept even though it does NOT fire inside the message list (proven
          // with raw CDP touch pairs 71 ms apart and an on-screen marker that
          // never appeared): the bubble's swipe/long-press wrapper shares the
          // gesture arena. Harmless where it does work; the button below is
          // the guaranteed route.
          onDoubleTap: () => showVideoFullscreen(context, widget.message),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // MediaPreviewFrame paints the ThumbHash behind this stack; the
              // tile only adds the video and its affordances on top.
              if (_ready)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _session!.controller!.value.size.width,
                    height: _session!.controller!.value.size.height,
                    child: VideoPlayer(_session!.controller!),
                  ),
                ),
              if (_loading)
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              else if (_error != null)
                Center(
                  child: Icon(
                    _error == VideoStageError.stillSending
                        ? Icons.cloud_upload_outlined
                        : Icons.broken_image,
                    size: 40,
                    color: Colors.white70,
                  ),
                )
              else if (!_playing)
                const Center(child: _PlayBadge()),
              _DurationChip(label: _durationLabel()),
              // Explicit escape hatch to fullscreen. A double tap ALSO works,
              // but it could not be made to fire reliably inside the message
              // list (the bubble's swipe/long-press wrapper shares the gesture
              // arena), so the only guaranteed route is a real button.
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showVideoFullscreen(context, widget.message),
                  child: Container(
                    key: const ValueKey('video_expand_button'),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.fullscreen,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Static play affordance over the media frame — scrim + glyph, the same
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

/// Small duration pill, bottom-left: the bubble's own time overlay owns the
/// bottom-right corner.
class _DurationChip extends StatelessWidget {
  final String? label;

  const _DurationChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final value = label;
    if (value == null) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
