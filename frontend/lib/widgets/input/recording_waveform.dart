import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Decorative recording waveform — bar heights are a function of [progress]
/// (an `AnimationController.value` in 0..1), NOT real microphone amplitude.
/// This makes it behave identically on web, PWA, and native (no dependence on
/// the `record` amplitude stream, which is unreliable on web/PWA).
class RecordingWaveform extends StatelessWidget {
  const RecordingWaveform({
    super.key,
    required this.progress,
    required this.color,
    this.barCount = 24,
    this.minBarFraction = 0.2,
  });

  /// 0..1 sweep value; pass `controller.value` from an `AnimatedBuilder`.
  final double progress;
  final Color color;
  final int barCount;

  /// Shortest bar as a fraction of the available height.
  final double minBarFraction;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _WaveformPainter(
        progress: progress,
        color: color,
        barCount: barCount,
        minBarFraction: minBarFraction,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.color,
    required this.barCount,
    required this.minBarFraction,
  });

  final double progress;
  final Color color;
  final int barCount;
  final double minBarFraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (barCount <= 0 || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    final slot = size.width / barCount;
    final barWidth = slot * 0.45;
    final centerY = size.height / 2;
    final phase = progress * 2 * math.pi;

    for (var i = 0; i < barCount; i++) {
      // Two offset sines give a lively, non-uniform sweep.
      final wave = (math.sin(phase + i * 0.7) +
              0.5 * math.sin(phase * 1.7 + i * 0.45)) /
          1.5;
      final norm = (wave + 1) / 2; // 0..1
      final fraction = minBarFraction + (1 - minBarFraction) * norm;
      final barHeight = size.height * fraction;
      final x = slot * i + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, centerY - barHeight / 2, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.barCount != barCount ||
      old.minBarFraction != minBarFraction;
}
