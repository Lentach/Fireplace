import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';

/// Full-width bar under the chat AppBar showing the pinned message preview.
class PinnedMessageBanner extends StatelessWidget {
  const PinnedMessageBanner({
    super.key,
    required this.previewText,
    required this.senderLabel,
    required this.onTap,
    required this.onUnpin,
  });

  final String previewText;
  final String senderLabel;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = RpgTheme.isDark(context);
    final mutedColor = isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;
    final borderColor = FireplaceColors.of(context).convItemBorder;

    return Semantics(
      label: l10n.pinnedMessageBannerSemantics,
      button: true,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.push_pin_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        senderLabel,
                        style: RpgTheme.bodyFont(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        previewText,
                        style: RpgTheme.bodyFont(fontSize: 12, color: mutedColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: l10n.pinnedMessageUnpinTooltip,
                  onPressed: onUnpin,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
