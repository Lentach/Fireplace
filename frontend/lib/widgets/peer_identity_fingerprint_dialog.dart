import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';

/// Side-by-side identity fingerprints for out-of-band verification.
///
/// This is the ONLY defence against a server-side key substitution. Fireplace's
/// server hands out prekey bundles and nothing in the Signal protocol proves a
/// bundle belongs to the claimed user, so two humans comparing these numbers —
/// in person or over a call where they recognise the voice — is what separates
/// "encrypted" from "encrypted to whoever the server said".
///
/// Reachable two ways on purpose:
///  * reactively, from [PeerIdentityChangedBanner] after a key change, and
///  * proactively, from the peer's Safety section, BEFORE anything goes wrong.
/// The proactive door matters because a first-contact substitution never
/// produces a change to warn about — there is no earlier key to differ from.
Future<void> showPeerIdentityFingerprintDialog({
  required BuildContext context,
  required int peerId,
  required String peerName,
}) {
  final l10n = AppLocalizations.of(context);
  // Capture the provider before opening the asynchronous dialog: the chat or
  // profile context can disappear while the user is comparing the numbers.
  final encryption = context.read<EncryptionProvider>();
  final fingerprints = Future.wait<String?>([
    encryption.getPeerIdentityFingerprint(peerId),
    encryption.getIdentityFingerprint(),
  ]);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      // Rebuilds when the warning clears, so the confirm button disappears the
      // moment it is used.
      final hasStandingWarning = dialogContext
          .select<EncryptionProvider, bool>(
            (e) => e.peersWithChangedIdentity.contains(peerId),
          );

      return AlertDialog(
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
          if (hasStandingWarning)
            TextButton(
              onPressed: () async {
                await encryption.acknowledgePeerIdentity(peerId);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(l10n.peerIdentityMarkVerifiedAction),
            ),
        ],
      );
    },
  );
}
