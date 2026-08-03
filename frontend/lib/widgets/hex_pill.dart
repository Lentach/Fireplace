import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An elongated horizontal hexagon: a rectangle with pointed end caps whose
/// corner angles match the app's pointy-top hexagons (120° interior angles).
///
/// This is the badge/pill shape of the invitation surfaces — counts and
/// status markers speak the same shape language as the hex avatars instead
/// of falling back to generic `borderRadius: 999` capsules.
class HexPill extends StatelessWidget {
  const HexPill({
    super.key,
    required this.label,
    required this.textStyle,
    required this.background,
    this.borderColor,
  });

  final String label;
  final TextStyle textStyle;
  final Color background;

  /// Hairline outline; null paints no border (for accent-filled pills).
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HexPillPainter(background: background, border: borderColor),
      child: Padding(
        // Horizontal padding covers the pointed caps (~0.29 * height each at
        // a 120° corner) plus breathing room, so text never hits the slopes.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Text(label, maxLines: 1, style: textStyle),
      ),
    );
  }
}

class _HexPillPainter extends CustomPainter {
  const _HexPillPainter({required this.background, this.border});

  final Color background;
  final Color? border;

  static Path _pillPath(Size size, double inset) {
    final h = size.height - inset * 2;
    // Horizontal run of a 120° corner: (h/2) * tan(30°).
    final cap = (h / 2) * math.tan(math.pi / 6);
    final left = inset;
    final right = size.width - inset;
    final top = inset;
    final bottom = size.height - inset;
    final mid = size.height / 2;
    return Path()
      ..moveTo(left, mid)
      ..lineTo(left + cap, top)
      ..lineTo(right - cap, top)
      ..lineTo(right, mid)
      ..lineTo(right - cap, bottom)
      ..lineTo(left + cap, bottom)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(_pillPath(size, 0.75), Paint()..color = background);
    if (border != null) {
      canvas.drawPath(
        _pillPath(size, 0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = border!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HexPillPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.border != border;
}
