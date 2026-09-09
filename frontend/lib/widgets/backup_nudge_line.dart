import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';

/// The one muted line at the top of Czaty for an account without a phrase
/// backup (multi-device spec §12 amendment (lxxxiii) clause 3). Tap opens the
/// recovery-key screen; the X snoozes it for a week. Same voice as
/// `PeerIdentityChangedNote`: a system line, not a card.
class BackupNudgeLine extends StatelessWidget {
  const BackupNudgeLine({
    super.key,
    required this.onTap,
    required this.onDismiss,
  });

  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mutedColor = RpgTheme.isDark(context)
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: mutedColor);
    return Semantics(
      button: true,
      child: InkWell(
        key: const Key('backup-nudge'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: mutedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.backupNudgeTitle,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('backup-nudge-dismiss'),
                icon: Icon(Icons.close, size: 16, color: mutedColor),
                tooltip: l10n.recoveryKeyLaterAction,
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
