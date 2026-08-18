import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';
import '../services/recovery_phrase.dart';
import 'glass/glass_dialog.dart';

/// What the user chose when asked for their recovery phrase.
sealed class RecoveryPromptResult {
  const RecoveryPromptResult();
}

/// They entered a well-formed phrase.
class RecoveryPromptPhrase extends RecoveryPromptResult {
  const RecoveryPromptPhrase(this.phrase);
  final String phrase;
}

/// They have no phrase and accept the full delay.
class RecoveryPromptWithoutPhrase extends RecoveryPromptResult {
  const RecoveryPromptWithoutPhrase();
}

/// Asks for the recovery phrase before starting an identity reset (§6.2.1).
///
/// The BIP39 checksum is validated locally first. The server rate-limits
/// attempts and locks the phrase out after five failures, so spending one of
/// those on a typo the client could have caught would be a poor trade.
///
/// Returns null when the user backed out entirely — which must NOT be read as
/// "start the slow one anyway".
Future<RecoveryPromptResult?> showRecoveryPhrasePrompt(BuildContext context) {
  return showDialog<RecoveryPromptResult>(
    context: context,
    builder: (_) => const _RecoveryPhrasePrompt(),
  );
}

class _RecoveryPhrasePrompt extends StatefulWidget {
  const _RecoveryPhrasePrompt();

  @override
  State<_RecoveryPhrasePrompt> createState() => _RecoveryPhrasePromptState();
}

class _RecoveryPhrasePromptState extends State<_RecoveryPhrasePrompt> {
  final TextEditingController _controller = TextEditingController();
  bool _malformed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final phrase = RecoveryPhrase.normalize(_controller.text);
    if (!RecoveryPhrase.isValid(phrase)) {
      setState(() => _malformed = true);
      return;
    }
    Navigator.of(context).pop(RecoveryPromptPhrase(phrase));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return GlassDialog(
      title: Text(l10n.recoveryPhrasePromptTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.recoveryPhrasePromptBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_malformed) setState(() => _malformed = false);
            },
            decoration: InputDecoration(
              hintText: l10n.recoveryPhrasePromptHint,
              errorText: _malformed ? l10n.recoveryPhraseMalformed : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const RecoveryPromptWithoutPhrase()),
          child: Text(l10n.recoveryPhraseNoneAction),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.recoveryPhraseUseAction),
        ),
      ],
    );
  }
}

/// The server's answer to a reset request, as a sentence for the user.
///
/// Pure on purpose: the refusals are exactly the ones a genuine owner hits
/// while recovering (a mistyped phrase that still passes the local checksum,
/// the lockout after five of those, the post-cancel cooldown), so the mapping
/// is worth pinning by test rather than burying in a widget callback. `null`
/// for an unrecognised status: say nothing rather than guess.
String? identityResetAnswerMessage(AppLocalizations l10n, String? status) {
  switch (status) {
    case 'pending':
      return l10n.identityResetStarted;
    case 'existing':
      return l10n.identityResetAlreadyRunning;
    case 'cooldown':
      return l10n.identityResetCooldown;
    case 'invalid_phrase':
      return l10n.identityResetPhraseRejected;
    case 'locked':
      return l10n.identityResetPhraseLocked;
    case EncryptionProvider.identityResetNoAnswerStatus:
    case null:
      // Silence is an answer too: nothing was started, and saying "started"
      // (or nothing at all) would leave the account unreachable and the user
      // believing otherwise.
      return l10n.identityResetNoAnswer;
    default:
      return null;
  }
}

/// True for the answers that mean nothing was started.
bool identityResetAnswerIsRefusal(String? status) =>
    status == null ||
    status == EncryptionProvider.identityResetNoAnswerStatus ||
    status == 'cooldown' ||
    status == 'invalid_phrase' ||
    status == 'locked';

/// Starts a reset, offering the recovery-key path first.
///
/// Every entry point into the ceremony goes through here so the question is
/// always asked in the same order: someone holding a phrase must never be
/// dropped into the 72-hour path just because the button they found was the
/// plain one. Backing out starts nothing at all.
///
/// The server's answer is surfaced by [IdentityResetPendingBanner], which is
/// mounted for the whole session: the answer can arrive after this dialog is
/// gone, and `existing` can arrive because another session started the
/// ceremony.
Future<void> startIdentityResetFlow(BuildContext context) async {
  final encryption = context.read<EncryptionProvider>();
  final result = await showRecoveryPhrasePrompt(context);
  switch (result) {
    case RecoveryPromptPhrase(:final phrase):
      encryption.requestIdentityReset(recoveryPhrase: phrase);
    case RecoveryPromptWithoutPhrase():
      encryption.requestIdentityReset();
    case null:
      // Dismissed: the user asked for nothing, so nothing starts.
      break;
  }
}
