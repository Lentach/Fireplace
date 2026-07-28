import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';

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

  Future<void> _showFingerprints(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Capture the provider before opening the asynchronous dialog. The chat
    // context can disappear while the user is comparing the numbers.
    final encryption = context.read<EncryptionProvider>();
    final fingerprints = Future.wait<String?>([
      encryption.getPeerIdentityFingerprint(peerId),
      encryption.getIdentityFingerprint(),
    ]);

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.peerIdentityFingerprintDialogTitle),
        content: FutureBuilder<List<String?>>(
          future: fingerprints,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 56,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final peerFingerprint = snapshot.data?[0];
            final ownFingerprint = snapshot.data?[1];
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.peerIdentityFingerprintDialogDescription(peerName)),
                  const SizedBox(height: 16),
                  Text(
                    l10n.peerIdentityFingerprintPeerLabel(peerName),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  if (peerFingerprint == null)
                    Text(l10n.peerIdentityFingerprintNoStoredKey)
                  else
                    SelectableText(peerFingerprint),
                  const SizedBox(height: 16),
                  Text(
                    l10n.yourIdentityFingerprint,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    ownFingerprint ?? l10n.identityFingerprintUnavailable,
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

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
