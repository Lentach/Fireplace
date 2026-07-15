import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

/// Shows a snackbar-style notification at the **top** of the screen
/// so it does not cover the chat input bar at the bottom.
void showTopSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(milliseconds: 2500),
}) {
  final overlay = Overlay.of(context);
  final theme = Theme.of(context);
  final bg = backgroundColor ?? theme.colorScheme.inverseSurface;
  // Pick the readable foreground for the actual fill: hardwired white failed
  // 4.5:1 on bright fills (#FF4444, #2AABEE).
  final textColor = backgroundColor == null
      ? theme.colorScheme.onInverseSurface
      : (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : Colors.black);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            color: bg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                message,
                style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  Future.delayed(duration, () {
    try {
      entry.remove();
    } catch (_) {}
  });
}
