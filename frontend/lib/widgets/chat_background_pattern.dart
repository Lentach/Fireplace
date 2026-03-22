import 'package:flutter/material.dart';

/// Draws a subtle dot pattern for chat background. Covers entire area.
class ChatBackgroundPattern extends StatelessWidget {
  final Widget child;
  final Color? dotColor;
  final Color? backgroundColor;

  const ChatBackgroundPattern({
    super.key,
    required this.child,
    this.dotColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = dotColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02));
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Container(
          width: w,
          height: h,
          color: backgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                size: Size(w, h),
                painter: _DotPatternPainter(
                  color: color,
                  devicePixelRatio: dpr,
                ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  final Color color;
  final double devicePixelRatio;

  _DotPatternPainter({
    required this.color,
    required this.devicePixelRatio,
  });

  static const double _spacing = 18;
  static const double _dotRadius = 0.9;

  /// Map logical coordinates to the nearest device-pixel center so every dot
  /// gets the same edge coverage (avoids brighter/darker columns when
  /// spacing × DPR is not an integer).
  Offset _snapLogicalToDevicePixel(double x, double y) {
    final dpr = devicePixelRatio;
    if (dpr <= 0) return Offset(x, y);
    return Offset(
      (x * dpr).round() / dpr,
      (y * dpr).round() / dpr,
    );
  }

  double _snapRadius() {
    final dpr = devicePixelRatio;
    if (dpr <= 0) return _dotRadius;
    return ((_dotRadius * dpr).round().clamp(1, 0x7fffffff)) / dpr;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final r = _snapRadius();
    for (double y = 0; y < size.height + _spacing; y += _spacing) {
      for (double x = 0; x < size.width + _spacing; x += _spacing) {
        final o = _snapLogicalToDevicePixel(x, y);
        canvas.drawCircle(o, r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPatternPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
