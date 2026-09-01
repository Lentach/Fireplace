import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/video_preview.dart';
import 'video_playback_session.dart';

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

/// `m:ss` (or `h:mm:ss` past the hour) for the seek-bar timestamps.
String _timestamp(Duration d) {
  final seconds = d.inSeconds.clamp(0, 359999);
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// How long the control chrome stays up during playback before fading.
/// Telegram uses ~3 s; matched here so the player feels familiar.
const _kChromeAutoHide = Duration(seconds: 3);

/// Fullscreen player, Telegram-shaped: a center play/pause button, a seek bar
/// with current/total timestamps, and chrome that auto-hides while playing.
/// A tap on the stage toggles the CHROME, never playback — playback state is
/// only ever changed by the button, so it is always visible when it changes.
///
/// Owns its own [VideoPlaybackSession]: the dialog is torn down independently
/// of the bubble, and sharing one decrypted buffer would mean neither side
/// could safely free it.
class _VideoFullscreenView extends StatefulWidget {
  final MessageModel message;

  const _VideoFullscreenView({required this.message});

  @override
  State<_VideoFullscreenView> createState() => _VideoFullscreenViewState();
}

class _VideoFullscreenViewState extends State<_VideoFullscreenView> {
  VideoPlaybackSession? _session;
  bool _loading = true;
  VideoStageError? _error;
  bool _playing = false;
  bool _chromeVisible = true;
  int _positionSeconds = 0;
  Timer? _hideTimer;

  VideoPlayerController? get _controller => _session?.controller;

  bool get _ready => _session?.isReady ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerTick);
    _session?.dispose();
    super.dispose();
  }

  void _onControllerTick() {
    final value = _controller?.value;
    if (value == null || !mounted) return;
    final playing = value.isPlaying;
    final seconds = value.position.inSeconds;
    if (playing == _playing && seconds == _positionSeconds) return;
    setState(() {
      _positionSeconds = seconds;
      if (playing != _playing) {
        _playing = playing;
        if (playing) {
          _scheduleHide();
        } else {
          // Pause and end-of-clip both surface the chrome and pin it: a
          // stopped player must never sit behind invisible controls.
          _hideTimer?.cancel();
          _chromeVisible = true;
        }
      }
    });
  }

  Future<void> _load() async {
    final session = VideoPlaybackSession(
      message: widget.message,
      token: context.read<AuthProvider>().token ?? '',
    );
    _session = session;
    final failure = await session.load();
    if (!mounted) {
      session.dispose();
      return;
    }
    if (failure != null) {
      setState(() {
        _loading = false;
        _error = failure;
      });
      return;
    }
    session.controller!.addListener(_onControllerTick);
    setState(() {
      _loading = false;
      _playing = true;
    });
    _scheduleHide();
    await session.controller!.setLooping(false);
    await session.controller!.play();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_kChromeAutoHide, () {
      if (!mounted) return;
      if (_controller?.value.isPlaying ?? false) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) _scheduleHide();
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
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(child: _buildStage()),
          _buildChrome(context),
        ],
      ),
    );
  }

  /// Every control lives in one fading layer so it appears and hides as a
  /// unit. `IgnorePointer` while hidden: an invisible close button that still
  /// swallows taps would fight the chrome-revealing tap on the stage.
  Widget _buildChrome(BuildContext context) {
    final controller = _controller;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_chromeVisible,
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Stack(
            children: [
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
                Center(
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: const ValueKey('video_play_pause'),
                      iconSize: 44,
                      padding: const EdgeInsets.all(14),
                      icon: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _togglePlayback,
                    ),
                  ),
                ),
              if (_ready && controller != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VideoSeekBar(
                        controller: controller,
                        onScrubStart: () => _hideTimer?.cancel(),
                        onScrubEnd: () {
                          if (controller.value.isPlaying) _scheduleHide();
                        },
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
      final stillSending = error == VideoStageError.stillSending;
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
      onTap: _toggleChrome,
      child: Center(
        child: AspectRatio(
          // NOT controller.value.aspectRatio: that getter ignores
          // rotationCorrection, while VideoPlayer compensates internally
          // with a RotatedBox. Trusting it squashes every rotated phone
          // recording into a landscape box.
          aspectRatio: _rotationAwareAspectRatio(controller.value),
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

/// `position — draggable slider — total`. A Material [Slider] instead of
/// [VideoProgressIndicator]: the package scrubber is an 8 px strip with no
/// thumb and a hit target fingers routinely miss on device — the owner
/// could not seek at all. The slider gives a visible thumb, a 48 px-tall
/// gesture surface, and drag semantics that reliably win the arena over
/// the stage's chrome-toggle tap.
///
/// Subscribes to the controller itself via [ValueListenableBuilder] — the
/// same subscription [VideoProgressIndicator] had — so the thumb glides at
/// the controller's native cadence instead of stepping with the fullscreen
/// state's whole-second rebuild gate.
///
/// While dragging: [onScrubStart] lets the owner pin its chrome (the hide
/// timer must not fire under the finger), the thumb and position label
/// follow the finger, the controller is seeked live so the frame scrubs
/// like Telegram, and [onScrubEnd] lets the owner re-arm auto-hide.
class VideoSeekBar extends StatefulWidget {
  const VideoSeekBar({
    super.key,
    required this.controller,
    this.onScrubStart,
    this.onScrubEnd,
  });

  final VideoPlayerController controller;
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  @override
  State<VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<VideoSeekBar> {
  /// Non-null while the user is dragging, in milliseconds. Drives both the
  /// thumb and the position label so the UI tracks the finger, not the
  /// (lagging) controller position.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds;
        // A not-yet-known duration would make the slider's max 0; render the
        // bar inert until the controller reports one.
        final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
        final positionMs = (_dragMs ??
                value.position.inMilliseconds.toDouble())
            .clamp(0.0, maxMs);
        return Row(
          children: [
            Text(
              _timestamp(Duration(milliseconds: positionMs.round())),
              key: const ValueKey('video_position_label'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  // Same media-scrim precedent as the bubble's time chip: a
                  // scrim over arbitrary frames is theme-independent.
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.15),
                ),
                child: Slider(
                  key: const ValueKey('video_seek_slider'),
                  max: maxMs,
                  value: positionMs,
                  onChangeStart: durationMs <= 0
                      ? null
                      : (v) {
                          widget.onScrubStart?.call();
                          setState(() => _dragMs = v);
                        },
                  onChanged: durationMs <= 0
                      ? null
                      : (v) {
                          setState(() => _dragMs = v);
                          widget.controller
                              .seekTo(Duration(milliseconds: v.round()));
                        },
                  onChangeEnd: durationMs <= 0
                      ? null
                      : (v) {
                          widget.controller
                              .seekTo(Duration(milliseconds: v.round()));
                          setState(() => _dragMs = null);
                          widget.onScrubEnd?.call();
                        },
                ),
              ),
            ),
            Text(
              _timestamp(value.duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }

}
