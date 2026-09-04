import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/passcode_provider.dart';
import '../services/local_data_eraser.dart';
import '../theme/rpg_theme.dart';
import '../utils/passcode_autolock.dart';
import '../widgets/passcode_entry_view.dart';
import '../widgets/settings_console.dart';

/// The lock screen: the only thing a locked user can interact with.
///
/// It deliberately shows no account information — no avatar, no username, no
/// unread counts. A lock screen that names the account leaks exactly what the
/// person holding the phone was not supposed to learn.
///
/// There is NO password door (owner ruling 2026-09-04). A recovery path that
/// the account password can walk through is not a lock, and no key-derived
/// lock in the field ships one: Telegram tells the user "if you forget your
/// passcode, you'll need to reinstall the app", Threema says "there is no way
/// to recover lost PIN codes", Phantom offers "Reset & wipe app". The only
/// way past a forgotten code here is the same: destroy what it guards.
class PasscodeUnlockScreen extends StatefulWidget {
  const PasscodeUnlockScreen({super.key, required this.onErase});

  /// Destroys every local store, then signs out. Injected so this screen
  /// never reaches for AuthProvider itself (and stays mountable in a widget
  /// test with only PasscodeProvider in scope).
  final Future<LocalDataEraseReport> Function() onErase;

  @override
  State<PasscodeUnlockScreen> createState() => _PasscodeUnlockScreenState();
}

class _PasscodeUnlockScreenState extends State<PasscodeUnlockScreen> {
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _erasePanelOpen = false;
  bool _erasing = false;
  bool _erasePartial = false;
  Timer? _cooldownTicker;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(_onConfirmChanged);
  }

  void _onConfirmChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _confirm.removeListener(_onConfirmChanged);
    _confirm.dispose();
    super.dispose();
  }

  void _ensureCooldownTicker(Duration? remaining) {
    if (remaining == null) {
      _cooldownTicker?.cancel();
      _cooldownTicker = null;
      return;
    }
    _cooldownTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _attempt(String code) async {
    final passcode = context.read<PasscodeProvider>();
    final l10n = AppLocalizations.of(context);
    final result = await passcode.unlock(code);
    if (!mounted) return;
    setState(() {
      _error = switch (result) {
        PasscodeUnlockResult.ok => null,
        PasscodeUnlockResult.wrong => l10n.passcodeWrong,
        PasscodeUnlockResult.temporarilyBlocked => null,
        PasscodeUnlockResult.unavailable => l10n.passcodeUnavailable,
      };
    });
  }

  Future<void> _erase(AppLocalizations l10n) async {
    if (_erasing) return;
    if (!_confirmationTyped(l10n)) return;
    setState(() {
      _erasing = true;
      _erasePartial = false;
    });
    final report = await widget.onErase();
    if (!mounted) return;
    setState(() {
      _erasing = false;
      // A destructive action that promised a clean slate must admit when it
      // did not get one, or the user walks away believing data is gone.
      _erasePartial = !report.complete;
    });
  }

  /// The confirmation word is compared case-insensitively, and every locale's
  /// word is deliberately ASCII (`ERASE`, `USUN`): this screen is the only
  /// thing on display when a locked-out user needs it, and a word with a
  /// diacritic would be untypeable without the right IME installed — found
  /// while verifying on an emulator with an English keyboard, 2026-09-04.
  bool _confirmationTyped(AppLocalizations l10n) =>
      _confirm.text.trim().toUpperCase() ==
      l10n.passcodeEraseConfirmWord.toUpperCase();

  /// Inline rather than a dialog ON PURPOSE: this screen lives ABOVE the
  /// app's Navigator (see `widgets/passcode_gate.dart`), so `showDialog` has
  /// no Navigator ancestor to push onto. An inline panel also keeps the
  /// barrier a single opaque surface with nothing pushed over it.
  Widget _erasePanel(AppLocalizations l10n, FireplaceColors colors) {
    final colorScheme = Theme.of(context).colorScheme;
    final armed = _confirmationTyped(l10n) && !_erasing;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.passcodeNoRecovery,
            textAlign: TextAlign.center,
            style: RpgTheme.bodyFont(fontSize: 13, color: colors.mutedText),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.passcodeEraseWarning,
            textAlign: TextAlign.center,
            style: RpgTheme.bodyFont(fontSize: 13, color: colorScheme.error),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('passcode-erase-field'),
            controller: _confirm,
            enabled: !_erasing,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            // No `onChanged`: on the web IME path the engine can push the
            // edited value straight into the controller without the callback
            // ever firing, which left this button dead while the field
            // visibly held the confirmation word (caught in live QA
            // 2026-09-04). The controller listener sees every change.
            decoration: InputDecoration(
              hintText: l10n.passcodeEraseConfirmHint(
                l10n.passcodeEraseConfirmWord,
              ),
              border: const OutlineInputBorder(),
            ),
            style: RpgTheme.bodyFont(
              fontSize: 15,
              color: colorScheme.onSurface,
            ),
          ),
          if (_erasePartial) ...[
            const SizedBox(height: 12),
            Text(
              l10n.passcodeErasePartial,
              key: const Key('passcode-erase-partial'),
              textAlign: TextAlign.center,
              style: RpgTheme.bodyFont(fontSize: 13, color: colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                key: const Key('passcode-erase-cancel'),
                onPressed: _erasing
                    ? null
                    : () => setState(() {
                        _erasePanelOpen = false;
                        _erasePartial = false;
                        _confirm.clear();
                      }),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('passcode-erase-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                onPressed: armed ? () => _erase(l10n) : null,
                child: Text(
                  _erasing ? l10n.passcodeErasing : l10n.passcodeEraseAction,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);
    final passcode = context.watch<PasscodeProvider>();
    final cooldown = passcode.lockoutRemaining;
    _ensureCooldownTicker(cooldown);

    final attemptsLeft = passcodeAttemptsRemaining(passcode.failedAttempts);
    final warnAttempts =
        cooldown == null &&
        passcode.failedAttempts > 0 &&
        attemptsLeft <= kPasscodeAttemptsWarningThreshold;

    return Scaffold(
      // Opaque by contract: this screen is the privacy barrier, so nothing of
      // the app underneath may show through.
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          const SizedBox(height: 44),
          ConsoleHexIcon(glyph: ConsoleGlyph.password, height: 56),
          Expanded(
            child: _erasePanelOpen
                // Replaces the entry surface instead of stacking under it:
                // the keypad plus a panel does not fit a short viewport, and
                // an escape hatch below the fold is one the locked-out user
                // cannot press.
                ? Center(child: _erasePanel(l10n, colors))
                : PasscodeEntryView(
                    mode: passcode.mode,
                    title: l10n.passcodeEnterTitle,
                    subtitle: warnAttempts
                        ? l10n.passcodeAttemptsLeft(attemptsLeft)
                        : null,
                    enabled: cooldown == null,
                    errorText: cooldown != null
                        ? l10n.passcodeBlocked(cooldown.inSeconds + 1)
                        : _error,
                    onSubmit: _attempt,
                    footer: TextButton(
                      key: const Key('passcode-forgot-link'),
                      onPressed: () => setState(() => _erasePanelOpen = true),
                      child: Text(
                        l10n.passcodeForgot,
                        style: RpgTheme.bodyFont(
                          fontSize: 13,
                          color: colors.mutedText,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Copy for "what this lock actually protects", chosen per platform because
/// the honest answer differs: on Android the verifier is Keystore-backed and
/// the window carries `FLAG_SECURE`, while on web it shares localStorage with
/// everything it guards. Bitwarden ships the same candor about its PIN
/// ("can weaken the level of encryption"); silence here would be a claim we
/// cannot support.
String passcodeScopeNote(AppLocalizations l10n) =>
    kIsWeb ? l10n.passcodeScopeNoteBrowser : l10n.passcodeScopeNoteDevice;
