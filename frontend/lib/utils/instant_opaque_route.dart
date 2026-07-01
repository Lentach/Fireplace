import 'package:flutter/material.dart';

/// Builds a full-screen route with no entry transition.
///
/// Chat entry on mobile must not expose the previous tab underneath. The default
/// iOS-style horizontal [MaterialPageRoute] transition can visibly freeze halfway
/// on mobile web, leaving the conversations tab and chat room painted together.
Route<T> instantOpaqueRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
}
