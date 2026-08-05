import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';
import 'peer_identity_fingerprint_dialog.dart';

/// Warns that a contact's Signal identity key changed.
///
/// Fireplace is trust-on-first-use and stays that way — the new key is accepted
/// so messages keep flowing. What changed is that the acceptance is no longer
/// SILENT. A peer key change is usually a reinstall, but it is also exactly
/// what a server inserting itself would look like, and the user is the only one
/// who can tell those apart (by asking the person over another channel).
///
/// Shown per conversation, for that peer only.
class PeerIdentityChangedBanner extends StatelessWidget {
  const PeerIdentityChangedBanner({
    required this.peerId,
    required this.peerName,
    super.key,
  });

  final int peerId;
  final String peerName;

  /// The fingerprint comparison lives in one place so the reactive (this
  /// banner) and proactive (peer Safety section) doors cannot drift apart.
  Future<void> _showFingerprints(BuildContext context) =>
      showPeerIdentityFingerprintDialog(
        context: context,
        peerId: peerId,
        peerName: peerName,
      );

  @override
  Widget build(BuildContext context) {
    final changed = context.select<EncryptionProvider, bool>(
      (e) => e.peersWithChangedIdentity.contains(peerId),
    );
    if (!changed) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              size: 18,
              color: colors.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.peerIdentityChangedWarning(peerName),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _showFingerprints(context),
              style: TextButton.styleFrom(
                foregroundColor: colors.onErrorContainer,
              ),
              child: Text(l10n.peerIdentityVerifyAction),
            ),
          ],
        ),
      ),
    );
  }
}
