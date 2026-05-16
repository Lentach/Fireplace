import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/message_model.dart';
import '../utils/message_expiry.dart';

/// Fireplace ember arc for read-based disappearing messages.
///
/// [dotted] = pre-read (TTL frozen, countdown not started).
/// Filled sweep = post-read countdown ([progress] 0…1).
class HearthFadeArcPainter extends CustomPainter {
  final Color color;
  final Color? trackColor;
  final double progress;
  final bool dotted;
  final double strokeWidth;

  const HearthFadeArcPainter({
    required this.color,
    this.trackColor,
    this.progress = 0,
    this.dotted = false,
    this.strokeWidth = 2.5,
  });

  static const double _startAngle = -math.pi / 2;
  static const double _sweepTotal = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (trackColor != null) {
      final trackPaint = Paint()
        ..color = trackColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      if (dotted) {
        _drawDashedArc(canvas, rect, trackPaint);
      } else {
        canvas.drawArc(rect, _startAngle, _sweepTotal, false, trackPaint);
      }
    }

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (dotted) {
      _drawDashedArc(canvas, rect, arcPaint);
      return;
    }

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    canvas.drawArc(
      rect,
      _startAngle,
      _sweepTotal * clamped,
      false,
      arcPaint,
    );
  }

  void _drawDashedArc(Canvas canvas, Rect rect, Paint paint) {
    const dashCount = 12;
    final dashSweep = _sweepTotal / dashCount;
    final gapSweep = dashSweep * 0.45;
    final drawSweep = dashSweep - gapSweep;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        rect,
        _startAngle + i * dashSweep,
        drawSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(HearthFadeArcPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progress != progress ||
        oldDelegate.dotted != dotted ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Small arc indicator for bubble metadata rows.
class HearthFadeArcIndicator extends StatelessWidget {
  final MessageModel message;
  final Color color;
  final Color? trackColor;
  final double size;

  const HearthFadeArcIndicator({
    super.key,
    required this.message,
    required this.color,
    this.trackColor,
    this.size = 12,
  });

  static bool showsEphemeralState(MessageModel message) {
    if (isMessageExpired(message)) return false;
    if (message.disappearAfterSeconds != null && message.expiresAt == null) {
      return true;
    }
    if (message.expiresAt != null) {
      final remaining = message.expiresAt!.difference(DateTime.now());
      return !remaining.isNegative;
    }
    return false;
  }

  static bool isPreRead(MessageModel message) =>
      message.disappearAfterSeconds != null && message.expiresAt == null;

  static double? countdownProgress(MessageModel message, [DateTime? now]) {
    final expiresAt = message.expiresAt;
    if (expiresAt == null) return null;
    final n = now ?? DateTime.now();
    final remaining = expiresAt.difference(n);
    if (remaining.isNegative) return null;
    final totalSeconds = message.disappearAfterSeconds;
    if (totalSeconds != null && totalSeconds > 0) {
      return remaining.inSeconds / totalSeconds;
    }
    final span = expiresAt.difference(message.createdAt);
    if (span.inSeconds <= 0) return 1.0;
    return remaining.inSeconds / span.inSeconds;
  }

  static String? countdownLabel(MessageModel message, [DateTime? now]) {
    final expiresAt = message.expiresAt;
    if (expiresAt == null) return null;
    final remaining = expiresAt.difference(now ?? DateTime.now());
    if (remaining.isNegative) return null;
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h';
    }
    if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m';
    }
    return '${remaining.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final preRead = isPreRead(message);
    final progress = preRead ? 0.0 : (countdownProgress(message) ?? 0.0);

    return CustomPaint(
      size: Size(size, size),
      painter: HearthFadeArcPainter(
        color: color,
        trackColor: trackColor ?? color.withValues(alpha: 0.28),
        progress: progress,
        dotted: preRead,
        strokeWidth: size < 16 ? 1.8 : 2.5,
      ),
    );
  }
}

/// Hero-scale decorative arc for the timer sheet.
class HearthFadeArcHero extends StatelessWidget {
  final Color color;
  final Color trackColor;
  final double size;
  final double progress;

  const HearthFadeArcHero({
    super.key,
    required this.color,
    required this.trackColor,
    this.size = 72,
    this.progress = 0.85,
  });

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final child = CustomPaint(
      size: Size(size, size),
      painter: HearthFadeArcPainter(
        color: color,
        trackColor: trackColor,
        progress: progress,
        strokeWidth: 4,
      ),
    );
    if (disableMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.65, end: progress),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => CustomPaint(
        size: Size(size, size),
        painter: HearthFadeArcPainter(
          color: color,
          trackColor: trackColor,
          progress: value,
          strokeWidth: 4,
        ),
      ),
    );
  }
}

/// Compact duration label for composer banner and list hints.
String formatCompactDisappearingSeconds(int seconds) {
  if (seconds >= 86400) {
    final d = seconds ~/ 86400;
    return '${d}d';
  }
  if (seconds >= 3600) {
    final h = seconds ~/ 3600;
    return '${h}h';
  }
  if (seconds >= 60) {
    final m = seconds ~/ 60;
    return '${m}m';
  }
  return '${seconds}s';
}
