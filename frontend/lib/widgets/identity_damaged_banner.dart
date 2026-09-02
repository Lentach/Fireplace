import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';
import '../screens/devices_screen.dart';
import 'glass/glass_dialog.dart';
import 'identity_alert_banner.dart';
import 'top_snackbar.dart';

/// Shown when the stored Signal identity is damaged (present but incomplete)
/// or absent while the account already has one published elsewhere.
///
/// Initialization deliberately FAILS CLOSED in that state rather than minting a
/// new identity, because regenerating silently is precisely the bug that
/// destroys a user's history without telling them. The cost of failing closed
/// is that E2E never comes up, so it must never be silent either: without this
/// banner the user sees `[encrypted]` on every message, on every boot, with no
/// explanation and no reachable way out.
///
/// Two ways out, ordered by amendment (lxvii): the always-visible action is the
/// §5.1 link — a keyless install of an enrolled account is, first of all, a
/// second device, and linking is non-destructive. "Start fresh" is the remedy
/// for the rarer shape (the usual device lost its keys), is destructive, and
/// so lives in the disclosure behind its confirm dialog, which states exactly
/// what is lost (all undecrypted ciphertext) and what is not (history this
/// device already decrypted — the plaintext cache survives).
class IdentityDamagedBanner extends StatelessWidget {
  const IdentityDamagedBanner({super.key});

  Future<void> _confirmAndRecover(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final encryption = context.read<EncryptionProvider>();
    // GlassDialog, not a raw AlertDialog: it is the app's dialog shell (9 call
    // sites) and it already mirrors AlertDialog's route semantics and platform
    // label, so a screen reader still announces a dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
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
    if (!context.mounted) return;
    try {
      await encryption.recoverFromIncompleteIdentity();
    } catch (_) {
      // Key generation can fail (storage quota, platform error). Say so rather
      // than leaving a dead button and an unhandled async error.
      //
      // showTopSnackBar, not ScaffoldMessenger: the tier file records the bottom
      // snackbar as a regression because it covers the chat composer. The raw
      // exception is no longer interpolated either — it was untranslated
      // developer text in a user-facing surface, and it said nothing a user
      // could act on.
      if (!context.mounted) return;
      showTopSnackBar(
        context,
        l10n.identityDamagedRecoveryFailed,
        backgroundColor: Theme.of(context).colorScheme.error,
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
    return IdentityAlertBanner(
      icon: Icons.gpp_bad_outlined,
      title: l10n.identityDamagedTitle,
      detail: l10n.identityDamagedBody,
      // Foreground is pinned to onErrorContainer: the default TextButton colour
      // is the theme PRIMARY, which renders near-invisible on the red error
      // container (caught in a real Chrome render, not by analyze). The link
      // is the safe door, so it stays visible while the explanation is
      // collapsed — the devices screen hosts the device-side flow.
      action: TextButton(
        key: const Key('identity-damaged-link'),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
        style: TextButton.styleFrom(foregroundColor: colors.onErrorContainer),
        child: Text(l10n.devicesLinkThisDevice),
      ),
      // Disabled while running: key generation mints 100 prekeys, and a second
      // tap would race a concurrent identity write.
      secondaryAction: TextButton(
        key: const Key('identity-damaged-start-fresh'),
        onPressed: busy ? null : () => _confirmAndRecover(context),
        style: TextButton.styleFrom(foregroundColor: colors.onErrorContainer),
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
    );
  }
}
