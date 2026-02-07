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
  final textColor = backgroundColor != null ? Colors.white : theme.colorScheme.onInverseSurface;

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
