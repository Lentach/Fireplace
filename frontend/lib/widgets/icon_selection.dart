import 'package:flutter/widgets.dart';

/// How far an icon is into its SELECTED state, published by whatever chrome
/// owns the selection (currently the bottom nav) and read by icons that can
/// draw a selected variant of themselves.
///
/// This exists so the two sides stay decoupled: `GlassBottomNav` takes plain
/// `Widget` icons and must not know the console glyph system exists, while
/// `ConsoleGlyphIcon` must not know it is being used in a nav. Both depend on
/// this one value instead of on each other. An icon that ignores it — every
/// plain `Icon` — just takes the ambient [IconTheme] color and cross-fades.
///
/// The pattern being expressed is the one every platform ships: a resting
/// outline and a heavier or filled SELECTED state. Material 3 says the icon
/// "becomes filled", iOS tab bars pair outline and filled symbols, Android
/// morphs the two through an `AnimatedVectorDrawable`. It works because the
/// change is mass, which survives being 24px where a transform or a stroke
/// reveal does not. Which form of mass suits a given mark is the icon's own
/// business: filling a closed silhouette flush just makes a black lump.
class IconSelection extends InheritedWidget {
  const IconSelection({
    super.key,
    required this.progress,
    this.activeColor,
    required super.child,
  });

  /// 0 = resting, 1 = fully selected. The default when no ancestor provides a
  /// value is 0, so an icon outside selectable chrome renders as its plain
  /// resting mark.
  final double progress;

  /// The color the solid state floods in. Held separately from the ambient
  /// [IconTheme] because that one is lerped by [progress] for the benefit of
  /// icons that cannot draw a partial state — using the lerped value for the
  /// flood would tint the fill toward the outline color and mute the change.
  final Color? activeColor;

  static IconSelection? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IconSelection>();

  static double progressOf(BuildContext context) => of(context)?.progress ?? 0;

  @override
  bool updateShouldNotify(IconSelection oldWidget) =>
      oldWidget.progress != progress || oldWidget.activeColor != activeColor;
}
