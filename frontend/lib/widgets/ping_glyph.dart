import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fireplace's shared ping mark: a centerless eight-ray attention pulse.
///
/// Cardinal rays are longer than diagonal rays so the mark stays legible from
/// the compact message indicator through the full-screen ping effect.
class PingGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const PingGlyph({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PingGlyphPainter(color)),
    );
  }
}

class _PingGlyphPainter extends CustomPainter {
  final Color color;

  const _PingGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = shortestSide * 0.105
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var index = 0; index < 8; index++) {
      final angle = index * math.pi / 4 - math.pi / 2;
      final isCardinal = index.isEven;
      final innerRadius = shortestSide * (isCardinal ? 0.215 : 0.225);
      final outerRadius = shortestSide * (isCardinal ? 0.455 : 0.385);
      final direction = Offset(math.cos(angle), math.sin(angle));

      canvas.drawLine(
        center + direction * innerRadius,
        center + direction * outerRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PingGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
