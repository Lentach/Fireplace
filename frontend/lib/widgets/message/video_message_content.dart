import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import 'media_preview_frame.dart';
import 'video_fullscreen_view.dart';

/// Video message bubble: a static poster. A tap opens [showVideoFullscreen] —
/// the Telegram model, where ALL playback lives in the fullscreen player and
/// the bubble never owns a [VideoPlayerController].
///
/// This is deliberate twice over. A scrolling list must never hold N live
/// players or N decrypted multi-megabyte buffers, and the bubble sits inside
/// the message row's swipe/long-press gesture wrapper, which was PROVEN to eat
/// taps unpredictably (raw CDP touch pairs 71 ms apart never fired a
/// double-tap here). In-place playback therefore had invisible state — a
/// playing video with no pause affordance — which is exactly the defect the
/// fullscreen-only model removes: one tap, one destination, real controls.
///
/// The frame's aspect ratio comes from `mediaWidth`/`mediaHeight` in the E2E
/// envelope, written at send time by the composer's `probeVideoPreview` pass.
/// Messages sent before that existed carry neither and fall back to
/// [MediaPreviewFrame.legacyHeight] — upgrade-only, never a regression.
///
/// Message content is a motion-banned zone: no entrance animation.
class VideoMessageContent extends StatelessWidget {
  final MessageModel message;

  const VideoMessageContent({super.key, required this.message});

  /// `m:ss` from the envelope's `mediaDuration`. Null when the sending
  /// platform could not read the container's duration.
  String? _durationLabel() {
    final seconds = message.mediaDuration;
    if (seconds == null || seconds <= 0) return null;
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final remainder = duration.inSeconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).videoMessage,
      button: true,
      child: MediaPreviewFrame(
        mediaWidth: message.mediaWidth,
        mediaHeight: message.mediaHeight,
        mediaThumbHash: message.mediaThumbHash,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showVideoFullscreen(context, message),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // MediaPreviewFrame paints the ThumbHash behind this stack; the
              // tile only adds the play affordance and duration on top.
              const Center(child: _PlayBadge()),
              _DurationChip(label: _durationLabel()),
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
