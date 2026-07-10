import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

/// The ONE Liquid Glass building block (accepted spec:
/// `docs/design/liquid-glass/SPEC.md` §2). Every glass surface in the app —
/// top-bar capsules, bottom nav pill, composer pill, panels/sheets — goes
/// through this widget. Do NOT hand-roll `BackdropFilter`s elsewhere.
///
/// Recipe: `ClipRRect` → `BackdropFilter(blur σ22 + saturate ×1.7)` →
/// per-theme fill + 1px border + inner top highlight, drop shadow outside
/// the clip, the whole thing isolated in a `RepaintBoundary`. Blur radius is
/// static by design — never animate it.
///
/// Opaque fallback (spec §7): solid `GlassTheme.opaqueFill`, same geometry,
/// no filter. Triggers: `MediaQuery.highContrast` (reactive) or the
/// compile-time [GlassSurface.reduceTransparency] switch
/// (`--dart-define=REDUCE_TRANSPARENCY=true`).
class GlassSurface extends StatelessWidget {
  /// Compile-time kill-switch: forces the opaque fallback everywhere
  /// (low-end escape hatch; also the NO-GO ship mode). Immutable by design —
  /// runtime fallback is driven reactively by `MediaQuery.highContrast`.
  static const bool reduceTransparency = bool.fromEnvironment(
    'REDUCE_TRANSPARENCY',
  );

  final BorderRadius borderRadius;
  final Widget? child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;

  /// Drop shadow under the floating surface. Disable for in-flow surfaces
  /// (e.g. panels attached to the composer stack).
  final bool shadow;

  /// Per-surface opaque fallback (spec §7) for media-dense surfaces where a
  /// large backdrop blur buys nothing visually (e.g. the GIF grid sheet).
  final bool forceOpaque;

  const GlassSurface({
    super.key,
    required this.borderRadius,
    this.child,
    this.width,
    this.height,
    this.padding,
    this.shadow = true,
    this.forceOpaque = false,
  });

  /// Blur sigma from the accepted spec.
  static const double blurSigma = 22;

  /// Saturation ×1.7 color matrix (Rec. 709 luma weights).
  static const ColorFilter saturate17 = ColorFilter.matrix(<double>[
    1.55118, -0.50064, -0.05054, 0, 0, //
    -0.14882, 1.19936, -0.05054, 0, 0, //
    -0.14882, -0.50064, 1.64946, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  static ui.ImageFilter get _backdropFilter => ui.ImageFilter.compose(
    outer: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
    inner: saturate17,
  );

  bool _opaque(BuildContext context) =>
      forceOpaque || reduceTransparency || MediaQuery.highContrastOf(context);

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final opaque = _opaque(context);

    Widget surface = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: opaque ? glass.opaqueFill : glass.fill,
        borderRadius: borderRadius,
        border: Border.all(color: glass.border),
      ),
      child: child,
    );

    if (!opaque) {
      // Inner top highlight hairline, inside the clip, above the fill.
      surface = Stack(
        children: [
          surface,
          Positioned(
            top: 1,
            left: borderRadius.topLeft.x * 0.6,
            right: borderRadius.topRight.x * 0.6,
            height: 1,
            child: IgnorePointer(child: ColoredBox(color: glass.highlight)),
          ),
        ],
      );
      surface = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(filter: _backdropFilter, child: surface),
      );
    }

    return RepaintBoundary(
      child: shadow
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                boxShadow: [glass.shadow],
              ),
              child: surface,
            )
          : surface,
    );
  }
}

/// Stadium-shaped [GlassSurface] — nav / composer / title pills.
class GlassPill extends StatelessWidget {
  final Widget? child;
  final double height;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final bool forceOpaque;

  const GlassPill({
    super.key,
    this.child,
    required this.height,
    this.width,
    this.padding,
    this.shadow = true,
    this.forceOpaque = false,
  });

  @override
  Widget build(BuildContext context) => GlassSurface(
    borderRadius: BorderRadius.circular(height / 2),
    height: height,
    width: width,
    padding: padding,
    shadow: shadow,
    forceOpaque: forceOpaque,
    child: child,
  );
}

/// Circular [GlassSurface] — icon-button capsules (back, add, avatar ring).
class GlassCircle extends StatelessWidget {
  final Widget? child;
  final double size;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final bool forceOpaque;

  const GlassCircle({
    super.key,
    this.child,
    required this.size,
    this.padding,
    this.shadow = true,
    this.forceOpaque = false,
  });

  @override
  Widget build(BuildContext context) => GlassSurface(
    borderRadius: BorderRadius.circular(size / 2),
    height: size,
    width: size,
    padding: padding,
    shadow: shadow,
    forceOpaque: forceOpaque,
    child: child,
  );
}
