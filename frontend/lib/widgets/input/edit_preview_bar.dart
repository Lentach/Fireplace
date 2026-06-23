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
    final isDark = RpgTheme.isDark(context);
    final fc = FireplaceColors.of(context);
    final borderColor = Theme.of(context).colorScheme.primary;
    final mutedColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        border: Border(
          left: BorderSide(color: borderColor, width: 4),
          bottom: BorderSide(color: fc.tabBorder),
        ),
      ),
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
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            color: mutedColor,
          ),
        ],
      ),
    );
  }
}
