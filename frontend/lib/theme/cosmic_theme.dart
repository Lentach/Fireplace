import 'package:flutter/material.dart';

/// Marker + tokens for the Cosmic theme's animated starfield backdrop.
///
/// Present ONLY in the `cosmic` [ThemeData]'s extension list; every other theme
/// resolves [maybeOf] to null and renders no starfield. Ported 1:1 from the
/// Fireplace landing hero starfield (`landing/src/scripts/util.ts` `makeStars`
/// / `drawStars`, `landing/src/styles/landing.css` `:root`):
/// - [baseColor]: near-black space fill under the stars (site body is flat
///   `#000`; we use a hair of blue so it reads as space, not a dead panel).
/// - [starColor]: star tint `rgb(190,220,240)` from `drawStars`. Alpha is
///   animated in the painter (`0.22 + 0.45·|sin(phase + t·speed)|`), NOT here.
/// - [density]: star count across the whole viewport. The site uses 240 (hero)
///   / 200 (outro) for a full DESKTOP canvas; on a phone that count is denser
///   per-area. The spike (tool/STARFIELD_SPIKE_RESULTS.md) showed 240 adds a
///   starfield-attributable raster-p95 bump on the worst-case x86 emulator,
///   while 120 sits at the opaque floor — and 120 on a phone is STILL denser
///   per-area than the site's desktop hero. So the default is 120 (perf-safe,
///   visually faithful); 240 stays a documented owner variant.
@immutable
class CosmicBackdrop extends ThemeExtension<CosmicBackdrop> {
  final Color baseColor;
  final Color starColor;
  final int density;

  const CosmicBackdrop({
    required this.baseColor,
    required this.starColor,
    required this.density,
  });

  /// Site tint `190,220,240`, near-black base, 120 stars (perf-safe default;
  /// see the density note above and the spike results).
  static const CosmicBackdrop starfield = CosmicBackdrop(
    baseColor: Color(0xFF04060C),
    starColor: Color(0xFFBEDCF0),
    density: 120,
  );

  static CosmicBackdrop? maybeOf(BuildContext context) =>
      Theme.of(context).extension<CosmicBackdrop>();

  @override
  CosmicBackdrop copyWith({Color? baseColor, Color? starColor, int? density}) =>
      CosmicBackdrop(
        baseColor: baseColor ?? this.baseColor,
        starColor: starColor ?? this.starColor,
        density: density ?? this.density,
      );

  // Discrete backdrop: no cross-fade between star tints (there is only one
  // cosmic theme, so lerp is never exercised between two CosmicBackdrops).
  @override
  CosmicBackdrop lerp(covariant ThemeExtension<CosmicBackdrop>? other, double t) {
    if (other is! CosmicBackdrop) return this;
    return t < 0.5 ? this : other;
  }
}
