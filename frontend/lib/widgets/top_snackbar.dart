import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import 'glass/glass_top_bar.dart';

/// Shows a snackbar-style notification at the **top** of the screen
/// so it does not cover the chat input bar at the bottom.
void showTopSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(milliseconds: 2500),
  VoidCallback? onTap,
  String? actionLabel,
}) {
  assert(onTap == null || actionLabel != null);
  final overlay = Overlay.of(context);
  final theme = Theme.of(context);
  final bg = backgroundColor ?? theme.colorScheme.inverseSurface;
  // Pick the readable foreground for the actual fill: hardwired white failed
  // 4.5:1 on bright fills (#FF4444, #2AABEE).
  final textColor = backgroundColor == null
      ? theme.colorScheme.onInverseSurface
      : RpgTheme.readableOn(bg);
  // Snapshot the inset from the CALLER context (not the root OverlayEntry ctx)
  // so the toast clears the same app-bar band the triggering screen sees.
  final topInset = MediaQuery.paddingOf(context).top;

  late OverlayEntry entry;
  entry = OverlayEntry(
    // Sit below the app-bar band (status-bar inset + toolbar height) so the
    // opaque fill never covers the back arrow it used to overlap at top:0.
    // IgnorePointer is kept so this informational overlay never intercepts
    // taps for whatever sits under it.
    builder: (_) => Positioned(
      top: topInset + GlassTopBar.capsuleHeight + 16 + 8,
      left: 16,
      right: 16,
      child: onTap == null
          ? IgnorePointer(
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: bg,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Text(
                    message,
                    style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
                  ),
                ),
              ),
            )
          : Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              color: bg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        style: RpgTheme.bodyFont(
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        entry.remove();
                        onTap();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: RpgTheme.readableOn(bg),
                        textStyle: RpgTheme.bodyFont(
                          fontSize: 14,
                          color: RpgTheme.readableOn(bg),
                        ),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
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
