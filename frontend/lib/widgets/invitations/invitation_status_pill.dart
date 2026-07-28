import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';
import '../../theme/rpg_theme.dart';

enum InvitationStatusPillKind { pending, ready }

/// A compact, solid status marker for invitation rows.
///
/// It deliberately does not use a glass widget: invitation rows live in the
/// opaque content layer, while glass is reserved for floating chrome.
class InvitationStatusPill extends StatelessWidget {
  final String label;
  final InvitationStatusPillKind kind;

  const InvitationStatusPill({
    super.key,
    required this.label,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = switch (kind) {
      InvitationStatusPillKind.pending => GlassTheme.of(context).opaqueFill,
      InvitationStatusPillKind.ready => colorScheme.primary,
    };
    final foreground = switch (kind) {
      InvitationStatusPillKind.pending => colorScheme.onSurface,
      InvitationStatusPillKind.ready => colorScheme.onPrimary,
    };

    // The pending fill is `opaqueFill`, which is exactly the row's own surface
    // colour now that rows are forceOpaque — without an outline the pill would be
    // invisible and only its bold text would imply the shape. `mutedText` is used
    // rather than `borderColor` because the blue border token measures 1.92:1 on
    // that fill, well under the ~3:1 a UI component boundary needs. The ready pill
    // sits on the accent and needs no outline.
    final colors = FireplaceColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: kind == InvitationStatusPillKind.pending
            ? Border.all(color: colors.mutedText)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: RpgTheme.bodyFont(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
