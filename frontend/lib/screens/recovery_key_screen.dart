import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/encryption_provider.dart';
import '../services/recovery_phrase.dart';
import '../theme/rpg_theme.dart';
import '../widgets/glass/glass_top_bar.dart';
import '../widgets/top_snackbar.dart';

/// Recovery key enrolment (multi-device spec §6.2.1).
///
/// What this buys the user: if they ever lose their keys, presenting this
/// phrase shortens the identity reset from 72 hours to 1. It does not skip the
/// reset, and it does not silence the notifications — so the copy promises
/// exactly that and nothing more.
///
/// The phrase is generated here, shown ONCE, and never written to local
/// storage: a phrase kept on the device would be destroyed by the same event
/// it exists to recover from. Only an Argon2id verifier reaches the server.
class RecoveryKeyScreen extends StatefulWidget {
  const RecoveryKeyScreen({super.key});

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  /// Held in memory only, for as long as this screen is open.
  List<String>? _words;
  bool _saving = false;

  @override
  void dispose() {
    // Not security theatre against a memory dump — just no reason to keep it
    // reachable once the screen is gone.
    _words = null;
    super.dispose();
  }

  void _generate() => setState(() => _words = RecoveryPhrase.generate());

  Future<void> _confirmSaved() async {
    final words = _words;
    if (words == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    final encryption = context.read<EncryptionProvider>();

    setState(() => _saving = true);
    encryption.clearRecoveryKeySetResult();
    // Enrolment and later verification MUST produce byte-identical strings —
    // the server compares an Argon2id hash, so any divergence fails the check
    // and burns one of the few attempts before lockout. Both sides go through
    // normalize() so they cannot drift apart.
    encryption.setRecoveryKey(RecoveryPhrase.normalize(words.join(' ')));

    // The server answers on the socket; wait briefly rather than claiming
    // success the moment the emit returns.
    bool? result;
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      result = encryption.recoveryKeySetResult;
      if (result != null) break;
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (result == true) {
      encryption.clearRecoveryKeySetResult();
      setState(() => _words = null);
      showTopSnackBar(context, l10n.recoveryKeySaved);
      Navigator.of(context).pop();
      return;
    }
    // Nothing was stored, so the phrase on screen is worthless — say so
    showTopSnackBar(
      context,
      l10n.recoveryKeySaveFailed,
      backgroundColor: Theme.of(context).colorScheme.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final words = _words;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: GlassTopBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.recoveryKeyTitle,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top:
              MediaQuery.paddingOf(context).top +
              GlassTopBar.capsuleHeight +
              16,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
          left: 24,
          right: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.recoveryKeyExplainer,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (words == null)
              FilledButton(
                onPressed: _generate,
                child: Text(l10n.recoveryKeyGenerateAction),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: SelectableText(
                  words.join('  '),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    height: 1.7,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.recoveryKeyShownOnceWarning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: words.join(' ')),
                  );
                  if (context.mounted) {
                    showTopSnackBar(context, l10n.recoveryKeyCopied);
                  }
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(l10n.recoveryKeyCopyAction),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _confirmSaved,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.recoveryKeySavedAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
