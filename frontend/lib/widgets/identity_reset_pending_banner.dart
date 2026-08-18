import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import 'recovery_phrase_prompt.dart';
import '../providers/encryption_provider.dart';

/// Phase 0b reset ceremony (multi-device spec §6.2): somebody asked the server
/// to let this account install new encryption keys, and a countdown is running.
///
/// This banner IS the protection. The delay only matters if the account owner
/// sees it and can stop it, so the cancel action is prominent, needs no key,
/// and is available from any signed-in session for the whole window. Every
/// session gets this — the request does not have to come from this device.
///
/// The countdown ticks locally against a server-issued deadline; the server
/// remains the authority and re-states it on every reconnect.
class IdentityResetPendingBanner extends StatefulWidget {
  const IdentityResetPendingBanner({super.key});

  @override
  State<IdentityResetPendingBanner> createState() =>
      _IdentityResetPendingBannerState();
}

class _IdentityResetPendingBannerState
    extends State<IdentityResetPendingBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // One tick a minute is enough for a 72 h (or 1 h) countdown and keeps the
    // banner from repainting the shell every second.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Coarse, human remaining time: hours while there is more than one left,
  /// minutes below that. Deliberately never seconds — this is a 72 h window,
  /// not a stopwatch.
  String _remaining(AppLocalizations l10n, DateTime deadline) {
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) return l10n.identityResetAnyMoment;
    if (left.inHours >= 1) return l10n.identityResetHoursLeft(left.inHours);
    return l10n.identityResetMinutesLeft(left.inMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final deadline = context.select<EncryptionProvider, DateTime?>(
      (e) => e.identityResetDeadline,
    );
    // The server refused to publish this device's new keys. Without a surface
    // the user is left believing they recovered while peers keep encrypting to
    // an identity they no longer hold, so this state is as loud as a pending
    // ceremony — and its action is the only way out.
    final locked = context.select<EncryptionProvider, bool>(
      (e) => e.identityUploadLocked,
    );
    if (deadline == null && !locked) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final pending = deadline != null;
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
                pending ? Icons.lock_reset_outlined : Icons.key_off_outlined,
                color: colors.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending
                          ? l10n.identityResetPendingTitle
                          : l10n.identityUploadLockedTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pending
                          ? l10n.identityResetPendingBody(
                              _remaining(l10n, deadline),
                            )
                          : l10n.identityUploadLockedBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
              // Foreground pinned to onErrorContainer: theme primary is nearly
              // invisible on the error container (same reason as the 0a banner).
              TextButton(
                onPressed: () {
                  if (pending) {
                    context.read<EncryptionProvider>().cancelIdentityReset();
                  } else {
                    // Ask for a recovery key first: it is the difference
                    // between waiting an hour and waiting three days.
                    startIdentityResetFlow(context);
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: Text(
                  pending
                      ? l10n.identityResetCancelAction
                      : l10n.identityResetStartAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
