import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';

/// Chat wallpaper (accepted Liquid Glass spec §6): base color + a tiled
/// 240px flame-doodle pattern (flames, sparks, crossed logs, embers, smoke,
/// marshmallow stick) at whisper contrast. Tint comes from
/// `GlassTheme.wallpaperTint` unless overridden.
class ChatBackgroundPattern extends StatelessWidget {
  final Widget child;

  /// Doodle stroke color (opacity baked in). Defaults to the theme's
  /// `GlassTheme.wallpaperTint`.
  final Color? patternColor;
  final Color? backgroundColor;

  const ChatBackgroundPattern({
    super.key,
    required this.child,
    this.patternColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = patternColor ?? GlassTheme.of(context).wallpaperTint;
    return Container(
      color: backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _FlameDoodlePainter(color: color)),
          ),
          child,
        ],
      ),
    );
  }
}

class _FlameDoodlePainter extends CustomPainter {
  final Color color;

  _FlameDoodlePainter({required this.color});

  static const double _tile = 240;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (double ty = 0; ty < size.height; ty += _tile) {
      for (double tx = 0; tx < size.width; tx += _tile) {
        canvas.save();
        canvas.translate(tx, ty);
        canvas.clipRect(const Rect.fromLTWH(0, 0, _tile, _tile));
        _paintTile(canvas, paint);
        canvas.restore();
      }
    }
  }

  void _paintTile(Canvas c, Paint p) {
    _flame(c, p, const Offset(46, 28), 1.0);
    _spark(c, p, const Offset(150, 43), 13);
    _spark(c, p, const Offset(206, 48), 8);
    // Crossed logs.
    c.drawLine(const Offset(26, 118), const Offset(68, 140), p);
    c.drawLine(const Offset(24, 136), const Offset(70, 126), p);
    _flame(c, p, const Offset(118, 104), 0.72);
    // Smoke curl.
    final smoke = Path()..moveTo(190, 100);
    smoke.relativeCubicTo(-6, 8, 6, 12, 0, 20);
    smoke.relativeCubicTo(-6, 8, 6, 12, 0, 20);
    c.drawPath(smoke, p);
    // Embers.
    c.drawCircle(const Offset(222, 146), 3, p);
    c.drawCircle(const Offset(210, 160), 2.2, p);
    c.drawCircle(const Offset(106, 216), 3, p);
    c.drawCircle(const Offset(92, 200), 2.2, p);
    // Marshmallow on a stick.
    c.drawLine(const Offset(40, 190), const Offset(70, 160), p);
    c.drawCircle(const Offset(77, 163), 8, p);
    _spark(c, p, const Offset(136, 198), 12);
    _flame(c, p, const Offset(188, 196), 0.85);
  }

  /// Campfire flame doodle: outer lick, inner cut, base arc.
  void _flame(Canvas c, Paint p, Offset o, double s) {
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(s);
    final flame = Path()..moveTo(0, 0);
    flame.relativeCubicTo(10, 8, 6, 16, 2, 21);
    flame.relativeCubicTo(-3, 4, -3, 10, 3, 13);
    flame.relativeCubicTo(9, -3, 15, -12, 15, -21);
    flame.relativeCubicTo(0, -14, -11, -24, -20, -28);
    flame.relativeCubicTo(2, 5, 2, 11, 0, 15);
    flame.close();
    c.drawPath(flame, p);
    final base = Path()..moveTo(0, 34);
    base.arcToPoint(
      const Offset(20, 34),
      radius: const Radius.circular(16),
      clockwise: false,
    );
    c.drawPath(base, p);
    c.restore();
  }

  /// Four-point spark star.
  void _spark(Canvas c, Paint p, Offset center, double r) {
    final w = r * 0.28;
    final path = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + w, center.dy - w)
      ..lineTo(center.dx + r, center.dy)
      ..lineTo(center.dx + w, center.dy + w)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - w, center.dy + w)
      ..lineTo(center.dx - r, center.dy)
      ..lineTo(center.dx - w, center.dy - w)
      ..close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_FlameDoodlePainter oldDelegate) =>
      oldDelegate.color != color;
}
