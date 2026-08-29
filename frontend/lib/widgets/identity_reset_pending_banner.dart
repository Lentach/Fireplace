import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import 'recovery_phrase_prompt.dart';
import 'top_snackbar.dart';
import '../providers/encryption_provider.dart';
import 'identity_alert_banner.dart';

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

  /// The last request answer already shown, so a rebuild does not repeat it.
  String? _reportedAnswer;

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

  /// Says out loud what the server answered.
  ///
  /// Three of the five answers REFUSE to start anything, and a user who lost
  /// their keys can hit all three — a mistyped phrase, the lockout after five
  /// of those, or the cooldown that follows a cancel. Without this the button
  /// simply appears dead while the account stays unreachable.
  void _reportAnswer(String status) {
    if (_reportedAnswer == status) return;
    _reportedAnswer = status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final message = identityResetAnswerMessage(
        AppLocalizations.of(context),
        status,
      );
      context.read<EncryptionProvider>().clearIdentityResetRequestStatus();
      if (message == null) return;
      showTopSnackBar(
        context,
        message,
        backgroundColor: identityResetAnswerIsRefusal(status)
            ? Theme.of(context).colorScheme.error
            : null,
      );
    });
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
    // Watched here rather than in the dialog that sent the request: the answer
    // can land after that dialog is gone, and `existing` can arrive because
    // ANOTHER session started the ceremony.
    final answer = context.select<EncryptionProvider, String?>(
      (e) => e.identityResetRequestStatus,
    );
    if (answer != null) {
      _reportAnswer(answer);
    } else {
      _reportedAnswer = null;
    }
    if (deadline == null && !locked) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final pending = deadline != null;
    return IdentityAlertBanner(
      icon: pending ? Icons.lock_reset_outlined : Icons.key_off_outlined,
      title: pending
          ? l10n.identityResetPendingTitle
          : l10n.identityUploadLockedTitle,
      // The countdown is STATUS, not prose, so it stays visible while the
      // explanation is collapsed — the whole point of the delay is that someone
      // sees it running.
      summary: pending ? _remaining(l10n, deadline) : null,
      detail: pending
          ? l10n.identityResetPendingBody(_remaining(l10n, deadline))
          : l10n.identityUploadLockedBody,
      // Foreground pinned to onErrorContainer: theme primary is nearly
      // invisible on the error container (same reason as the 0a banner).
      action: TextButton(
        onPressed: () {
          if (pending) {
            context.read<EncryptionProvider>().cancelIdentityReset();
          } else {
            // Ask for a recovery key first: it is the difference between
            // waiting an hour and waiting three days.
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
    );
  }
}
