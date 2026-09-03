import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';
import '../screens/devices_screen.dart';
import 'identity_alert_banner.dart';

/// Shown when this install holds no usable Signal identity while the account
/// already has one published from another device.
///
/// Initialization deliberately FAILS CLOSED in that state rather than minting a
/// new identity, because regenerating silently is precisely the bug that
/// destroys a user's history without telling them. The cost of failing closed
/// is that E2E never comes up, so it must never be silent either: without this
/// banner the user sees `[encrypted]` on every message, on every boot, with no
/// explanation and no reachable way out.
///
/// The way out is the §5.1 link — a keyless install of an enrolled account is,
/// first of all, a second device, and linking is non-destructive. There is no
/// "start fresh" (amendment (lxxi)): the only thing that button could do was
/// mint an identity no peer trusts, and the registration lock refused its
/// upload anyway. A never-enrolled account never sees this banner — its keys
/// are generated without asking.
class IdentityDamagedBanner extends StatelessWidget {
  const IdentityDamagedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final damaged = context.select<EncryptionProvider, bool>(
      (e) => e.identityIncomplete,
    );
    if (!damaged) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return IdentityAlertBanner(
      icon: Icons.gpp_bad_outlined,
      title: l10n.identityDamagedTitle,
      detail: l10n.identityDamagedBody,
      // Foreground is pinned to onErrorContainer: the default TextButton colour
      // is the theme PRIMARY, which renders near-invisible on the red error
      // container (caught in a real Chrome render, not by analyze). The link
      // is the only door, so it stays visible while the explanation is
      // collapsed — the devices screen hosts the device-side flow.
      action: TextButton(
        key: const Key('identity-damaged-link'),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
        style: TextButton.styleFrom(foregroundColor: colors.onErrorContainer),
        child: Text(l10n.devicesLinkThisDevice),
      ),
    );
  }
}
