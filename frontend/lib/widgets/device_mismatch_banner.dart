import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';
import '../screens/devices_screen.dart';
import 'identity_alert_banner.dart';

/// Shown when the server-confirmed device id contradicts the (lxiv)
/// material-device stamp: this install's Signal material was provisioned for a
/// device that is no longer this session's device — the revoked device that
/// signed back in with the password.
///
/// E2E duty is refused while this state holds ([EncryptionProvider] keeps
/// `isE2EReady` false and publishes nothing), because operating under the
/// wrong device id is what silently clobbers the primary's published keys and
/// destroys peers' first messages. The way out is the §5.1 link ceremony, so
/// the action routes to the devices screen, which hosts it.
class DeviceMismatchBanner extends StatelessWidget {
  const DeviceMismatchBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mismatch = context.select<EncryptionProvider, bool>(
      (e) => e.deviceMaterialMismatch,
    );
    if (!mismatch) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return IdentityAlertBanner(
      icon: Icons.phonelink_erase_outlined,
      title: l10n.deviceMismatchTitle,
      detail: l10n.deviceMismatchBody,
      action: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DevicesScreen()),
        ),
        // Foreground pinned to onErrorContainer for the same contrast reason
        // as IdentityDamagedBanner (theme primary is near invisible on the
        // error container).
        style: TextButton.styleFrom(foregroundColor: colors.onErrorContainer),
        child: Text(l10n.deviceMismatchAction),
      ),
    );
  }
}
