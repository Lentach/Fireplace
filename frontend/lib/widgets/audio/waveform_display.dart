import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Scrubbable waveform widget — tap or drag to seek.
///
/// Accepts [waveformData] as a seed (message id) for per-message visual
/// variation, plus [position]/[duration] for the filled-vs-unfilled split.
class WaveformDisplay extends StatelessWidget {
  final int messageId;
  final Duration position;
  final Duration duration;
  final Color color;

  /// Called when the user taps or drags; provides the new playback position.
  final void Function(double localX, double width) onSeek;

  const WaveformDisplay({
    super.key,
    required this.messageId,
    required this.position,
    required this.duration,
    required this.color,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          onTapDown: duration.inMilliseconds > 0
              ? (d) => onSeek(d.localPosition.dx, w)
              : null,
          onHorizontalDragUpdate: duration.inMilliseconds > 0
              ? (d) => onSeek(d.localPosition.dx, w)
              : null,
          behavior: HitTestBehavior.opaque,
          child: duration.inMilliseconds > 0
              ? CustomPaint(
                  painter: WaveformPainter(
                    progress: position.inMilliseconds / duration.inMilliseconds,
                    color: color,
                    messageId: messageId,
                  ),
                  size: Size(w, 28),
                )
              : Container(
                  height: 28,
                  color: Colors.grey.withValues(alpha: 0.1),
                ),
        );
      },
    );
  }
}

/// Custom painter that draws a waveform with sine-wave height variation.
/// Bars to the left of [progress] are drawn filled; bars to the right are muted.
class WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int messageId; // seed for per-message waveform variation

  const WaveformPainter({
    required this.progress,
    required this.color,
    required this.messageId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final paintFilled = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const barCount = 50;
    final barWidth = size.width / barCount;
    final seed = messageId.abs() % 1000; // per-message variation (id can be negative for temp)

    for (int i = 0; i < barCount; i++) {
      // Wave-like pattern: multiple overlapping sine waves for natural variation.
      final t = (i + seed * 0.1) * 0.35;
      final wave1 = math.sin(t) * 0.4;
      final wave2 = math.sin(t * 2.3 + 1.5) * 0.2;
      final wave3 = math.sin(t * 0.7 + 3) * 0.15;
      final heightFactor = (0.5 + wave1 + wave2 + wave3).clamp(0.15, 0.95);
      final barHeight = size.height * heightFactor;

      final x = i * barWidth + barWidth / 2;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      final currentPaint = (i / barCount) <= progress ? paintFilled : paint;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), currentPaint);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.messageId != messageId;
  }
}
