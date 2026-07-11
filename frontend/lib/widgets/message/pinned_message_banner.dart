import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/glass_theme.dart';
import '../../theme/rpg_theme.dart';
import '../glass/glass_surface.dart';

/// Floating glass pill under the chat top chrome showing the pinned message
/// preview (owner ruling 2026-07-11: glass bubble, not the old full-width
/// strip).
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
    final glass = GlassTheme.of(context);
    final mutedColor = glass.onGlassMuted;

    return Semantics(
      label: l10n.pinnedMessageBannerSemantics,
      button: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
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
                            style: RpgTheme.bodyFont(
                              fontSize: 12,
                              color: mutedColor,
                            ),
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
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
