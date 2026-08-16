import 'package:flutter/material.dart';

/// Builds a full-screen route with no entry transition and a short fade-out
/// on pop.
///
/// Chat entry on mobile must not expose the previous tab underneath. The default
/// iOS-style horizontal [MaterialPageRoute] transition can visibly freeze halfway
/// on mobile web, leaving the conversations tab and chat room painted together.
/// The entry therefore stays opaque and zero-duration — do not touch it.
///
/// The pop used to be zero-duration too, which tore the whole route down in a
/// single un-animated frame and read as swipe-back lag. The reverse transition
/// is a 180ms fade instead: the zero-duration forward run snaps the animation
/// to 1.0 (so entry paints at full opacity from the first frame), and the pop
/// fades 1 → 0. Reduce-motion skips the fade.
Route<T> instantOpaqueRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return FadeTransition(opacity: animation, child: child);
    },
  );
}
