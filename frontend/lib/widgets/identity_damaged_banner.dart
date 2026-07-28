import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';

/// Shown when the stored Signal identity is damaged (present but incomplete).
///
/// Initialization deliberately FAILS CLOSED in that state rather than minting a
/// new identity, because regenerating silently is precisely the bug that
/// destroys a user's history without telling them. The cost of failing closed
/// is that E2E never comes up, so it must never be silent either: without this
/// banner the user sees `[encrypted]` on every message, on every boot, with no
/// explanation and no reachable way out.
///
/// The escape hatch is destructive, so it is explicit and confirmed, and the
/// dialog states exactly what is lost (all undecrypted ciphertext) and what is
/// not (history this device already decrypted — the plaintext cache survives).
class IdentityDamagedBanner extends StatelessWidget {
  const IdentityDamagedBanner({super.key});

  Future<void> _confirmAndRecover(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final encryption = context.read<EncryptionProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.identityDamagedConfirmTitle),
        content: Text(l10n.identityDamagedConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.identityDamagedConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await encryption.recoverFromIncompleteIdentity();
    } catch (e) {
      // Key generation can fail (storage quota, platform error). Say so rather
      // than leaving a dead button and an unhandled async error.
      messenger?.showSnackBar(
        SnackBar(content: Text('${l10n.identityDamagedTitle}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final damaged = context.select<EncryptionProvider, bool>(
      (e) => e.identityIncomplete,
    );
    if (!damaged) return const SizedBox.shrink();
    final busy = context.select<EncryptionProvider, bool>(
      (e) => e.identityRecoveryInFlight,
    );
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
                Icons.gpp_bad_outlined,
                color: colors.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.identityDamagedTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.identityDamagedBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
              // Disabled while running: key generation mints 100 prekeys, and a
              // second tap would race a concurrent identity write.
              //
              // Foreground is pinned to onErrorContainer: the default TextButton
              // colour is the theme PRIMARY, which renders near-invisible on the
              // red error container (caught in a real Chrome render, not by
              // analyze). This is the one action a user with damaged keys has.
              TextButton(
                onPressed: busy ? null : () => _confirmAndRecover(context),
                style: TextButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                ),
                child: busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onErrorContainer,
                        ),
                      )
                    : Text(l10n.identityDamagedAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
