import 'package:flutter/widgets.dart';

/// How an icon is transitioning into its active look, published by whatever
/// chrome owns the selection (currently the bottom nav) and read by icons
/// that know how to draw themselves progressively.
///
/// This exists so the two sides stay decoupled: `GlassBottomNav` takes plain
/// `Widget` icons and must not know the console glyph system exists, while
/// `ConsoleGlyphIcon` must not know it is being used in a nav. Both depend on
/// this one value instead of on each other. An icon that ignores it — every
/// `Icon` in the app — is simply unaffected.
class IconEntrance extends InheritedWidget {
  const IconEntrance({
    super.key,
    required this.progress,
    this.restColor,
    this.activeColor,
    required super.child,
  });

  /// How much of the ACTIVE look is drawn: 0 at rest, 1 fully active. The
  /// default when no ancestor provides a value is 1, so a glyph outside
  /// animated chrome renders as a finished mark.
  final double progress;

  /// The color the icon rests in, painted underneath at full strength while
  /// the transition runs.
  ///
  /// Load-bearing: without it a draw-on starts from an empty box, so a
  /// freshly selected icon blinks out and redraws instead of handing over.
  /// With it, the resting mark never leaves the screen and the active color
  /// simply sweeps across it.
  final Color? restColor;

  /// The color being swept on. Held separately from the ambient [IconTheme]
  /// because that one is lerped by [progress] for the benefit of icons that
  /// cannot draw themselves partially — using the lerped value for the sweep
  /// would make the first half of the sweep the same color as the underlay,
  /// i.e. invisible.
  final Color? activeColor;

  static IconEntrance? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IconEntrance>();

  static double progressOf(BuildContext context) => of(context)?.progress ?? 1;

  @override
  bool updateShouldNotify(IconEntrance oldWidget) =>
      oldWidget.progress != progress ||
      oldWidget.restColor != restColor ||
      oldWidget.activeColor != activeColor;
}
