import 'package:flutter/material.dart';

/// Scroll behavior for the whole app.
///
/// On Android, Material 3 wraps scrollables in [StretchingOverscrollIndicator], which
/// warps the entire screen when the user overscrolls (drag past list edge). That made
/// "tiles" and layout appear to pull apart vertically. Returning [child] disables it.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
