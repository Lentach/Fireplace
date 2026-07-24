import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Pointy-top hexagon geometry + avatar surface shared by the Contacts
/// honeycomb (`contact_network_view.dart`) and the Chats list tile, so both
/// tabs speak one shape language instead of drifting apart.

/// Width of a pointy-top hexagon relative to its height (sqrt(3) / 2).
const double kHexWidthRatio = 0.8660254037844386;

/// Pointy-top hexagon path centered on [c] with circumradius [r].
Path hexPath(Offset c, double r) {
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final a = -math.pi / 2 + i * math.pi / 3;
    final p = c + Offset(math.cos(a), math.sin(a)) * r;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// Up to two uppercase initials, `?` when the name has no usable characters.
String hexInitials(String value) {
  final parts = value
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  final initials = parts
      .take(2)
      .map((part) => part.substring(0, 1).toUpperCase())
      .join();
  return initials.isEmpty ? '?' : initials;
}

class HexClipper extends CustomClipper<Path> {
  const HexClipper();

  @override
  Path getClip(Size size) =>
      hexPath(Offset(size.width / 2, size.height / 2), size.height / 2 - 0.75);

  @override
  bool shouldReclip(covariant HexClipper oldClipper) => false;
}

/// The hex fill: the user's avatar covering the whole box, or the themed
/// surface + initials when there is no (loadable) avatar. Unclipped — the
/// caller owns the clip so it can also paint chrome over the result.
class HexAvatarSurface extends StatefulWidget {
  const HexAvatarSurface({
    super.key,
    required this.imageUrl,
    required this.initials,
    required this.surface,
    required this.initialsStyle,
  });

  final String? imageUrl;
  final String initials;
  final Color surface;
  final TextStyle initialsStyle;

  @override
  State<HexAvatarSurface> createState() => _HexAvatarSurfaceState();
}

class _HexAvatarSurfaceState extends State<HexAvatarSurface> {
  bool _imageLoadError = false;

  @override
  void didUpdateWidget(HexAvatarSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageLoadError = false;
    }
  }

  String _resolvedUrl() {
    final url = widget.imageUrl!;
    final isAbsolute = url.startsWith('http://') || url.startsWith('https://');
    // Same resolution as AvatarCircle: the per-upload UUID filename is the
    // cache key, no cache-busting query.
    return isAbsolute ? url : '${AppConfig.baseUrl}$url';
  }

  Widget _fallback() {
    return ColoredBox(
      color: widget.surface,
      child: Center(child: Text(widget.initials, style: widget.initialsStyle)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    if (url == null || url.trim().isEmpty || _imageLoadError) {
      return _fallback();
    }
    return Image.network(
      _resolvedUrl(),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _imageLoadError = true);
        });
        return _fallback();
      },
      loadingBuilder: (context, child, loadingProgress) =>
          loadingProgress == null ? child : _fallback(),
    );
  }
}

/// List-ready hex avatar: sized, clipped, hairline ring, optional ember ring
/// whose strength encodes recency (0 = cold, 1 = fresh).
class HexAvatar extends StatelessWidget {
  const HexAvatar({
    super.key,
    required this.size,
    required this.displayName,
    required this.imageUrl,
    required this.surface,
    required this.borderColor,
    required this.initialsStyle,
    this.ember = 0,
    this.emberColor,
  });

  /// Hexagon height; width follows [kHexWidthRatio].
  final double size;
  final String displayName;
  final String? imageUrl;
  final Color surface;
  final Color borderColor;
  final TextStyle initialsStyle;
  final double ember;
  final Color? emberColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * kHexWidthRatio,
      height: size,
      child: CustomPaint(
        foregroundPainter: HexRingPainter(
          borderColor: borderColor,
          ember: ember,
          emberColor: emberColor ?? Theme.of(context).colorScheme.primary,
        ),
        child: ClipPath(
          clipper: const HexClipper(),
          child: HexAvatarSurface(
            imageUrl: imageUrl,
            initials: hexInitials(displayName),
            surface: surface,
            initialsStyle: initialsStyle,
          ),
        ),
      ),
    );
  }
}

/// Hairline hex outline, plus an accent overlay whose opacity tracks [ember].
class HexRingPainter extends CustomPainter {
  const HexRingPainter({
    required this.borderColor,
    required this.emberColor,
    this.ember = 0,
  });

  final Color borderColor;
  final Color emberColor;
  final double ember;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.height / 2 - 0.75;
    canvas.drawPath(
      hexPath(c, r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = borderColor.withValues(alpha: 0.6),
    );
    if (ember > 0.01) {
      canvas.drawPath(
        hexPath(c, r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = emberColor.withValues(alpha: 0.12 + 0.6 * ember),
      );
    }
  }

  @override
  bool shouldRepaint(covariant HexRingPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor ||
      oldDelegate.emberColor != emberColor ||
      oldDelegate.ember != ember;
}
