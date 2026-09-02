import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';

/// The calm own-device-skew state (multi-device spec §12 amendments (xvii),
/// (xx).2).
///
/// Shown while a peer's in-band `senderListInfo` says our OWN devices disagree
/// about our own device list — which just means they have not finished syncing.
/// The state is bounded to that one re-fetch window, so a peer who keeps
/// claiming a newer version cannot pin this note on.
///
/// It deliberately borrows NOTHING from the identity/takeover surface
/// ([IdentityDamagedBanner], [OwnIdentityReplacedBanner],
/// [PeerIdentityChangedRow], all of which sit on `colorScheme.errorContainer`
/// behind a security glyph): **no security colour, no icon, no sound.**
/// Conflating a benign sync with an attack is how users learn to ignore real
/// warnings — so the muted body-small text below is the load-bearing part of
/// this widget, not incidental styling.
///
/// A standalone widget rather than a private build method precisely so it can
/// be rendered in isolation beside those three and asserted against them.
class DevicesSyncingNote extends StatelessWidget {
  const DevicesSyncingNote({super.key});

  @override
  Widget build(BuildContext context) {
    final mutedColor = RpgTheme.isDark(context)
        ? RpgTheme.mutedDark
        : RpgTheme.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        AppLocalizations.of(context).devicesSyncingNote,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: mutedColor),
      ),
    );
  }
}
