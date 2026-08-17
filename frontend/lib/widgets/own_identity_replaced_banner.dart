import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';

/// Phase 0a takeover alarm (multi-device spec §6.0): the server reported that
/// ANOTHER sign-in replaced this account's key bundle (`ownIdentityReplaced`
/// WS event / `identity_changed` push).
///
/// Wording rule (owner-ratified 2026-08-17): the same server branch fires on
/// every LEGITIMATE reinstall or new-browser sign-in, so the copy leads with
/// "new device/browser sign-in" and offers the takeover reading ("change your
/// password") as the variant — it must not scream "hacked".
///
/// Durable until explicitly dismissed: the alarm survives restarts because a
/// user who was not looking at the app when it fired must still learn about
/// it. Dismissal is the only thing that clears it.
class OwnIdentityReplacedBanner extends StatelessWidget {
  const OwnIdentityReplacedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final active = context.select<EncryptionProvider, bool>(
      (e) => e.ownIdentityReplacedAt != null,
    );
    if (!active) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.phonelink_lock_outlined,
                color: colors.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.ownIdentityReplacedTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.ownIdentityReplacedBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
              // Foreground pinned to onErrorContainer for the same contrast
              // reason as IdentityDamagedBanner (theme primary is near
              // invisible on the error container).
              TextButton(
                onPressed: () =>
                    context.read<EncryptionProvider>().dismissOwnIdentityReplaced(),
                style: TextButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                ),
                child: Text(l10n.ownIdentityReplacedDismissAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
