import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';

/// Shown above the input bar while editing a sent message. Mirrors
/// [ReplyPreviewBar] visually; the pencil icon + title distinguish edit mode.
class EditPreviewBar extends StatelessWidget {
  const EditPreviewBar({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fc = FireplaceColors.of(context);
    final borderColor = Theme.of(context).colorScheme.primary;
    // Per-theme token: the old `isDark ? white60 : black54` was one grey for
    // three dark themes and another for two light ones.
    final mutedColor = fc.mutedText;

    // Mirrors ReplyPreviewBar's rounded floating card.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fc.tabBorder),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 16, color: borderColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.messageEditingTitle,
                style: RpgTheme.bodyFont(
                  fontSize: 12,
                  color: borderColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              color: mutedColor,
            ),
          ],
        ),
      ),
    );
  }
}
