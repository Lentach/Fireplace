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
                painter: _DotPatternPainter(color: color),
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

  _DotPatternPainter({required this.color});

  static const double _spacing = 18;
  static const double _dotRadius = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 0; y < size.height + _spacing; y += _spacing) {
      for (double x = 0; x < size.width + _spacing; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPatternPainter oldDelegate) =>
      oldDelegate.color != color;
}
