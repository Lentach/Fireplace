import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/passcode_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/passcode_entry_view.dart';
import '../widgets/settings_console.dart';

/// The lock screen: the only thing a locked user can interact with.
///
/// It deliberately shows no account information — no avatar, no username, no
/// unread counts. A lock screen that names the account leaks exactly what the
/// person holding the phone was not supposed to learn.
class PasscodeUnlockScreen extends StatefulWidget {
  const PasscodeUnlockScreen({super.key, required this.onForgot});

  /// Runs the recovery path: clear the credential, then log out. Injected so
  /// this screen never reaches for AuthProvider itself (and stays mountable in
  /// a widget test with only PasscodeProvider in scope).
  final Future<void> Function() onForgot;

  @override
  State<PasscodeUnlockScreen> createState() => _PasscodeUnlockScreenState();
}

class _PasscodeUnlockScreenState extends State<PasscodeUnlockScreen> {
  String? _error;
  bool _forgotOpen = false;
  Timer? _cooldownTicker;

  @override
  void dispose() {
    _cooldownTicker?.cancel();
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

  /// Inline rather than a dialog ON PURPOSE: this screen lives ABOVE the
  /// app's Navigator (see `widgets/passcode_gate.dart`), so `showDialog` has
  /// no Navigator ancestor to push onto. An inline confirm also keeps the
  /// barrier a single opaque surface with nothing pushed over it.
  Widget _forgotPanel(AppLocalizations l10n, FireplaceColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            l10n.passcodeForgotExplainer,
            textAlign: TextAlign.center,
            style: RpgTheme.bodyFont(fontSize: 13, color: colors.mutedText),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                key: const Key('passcode-forgot-cancel'),
                onPressed: () => setState(() => _forgotOpen = false),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('passcode-forgot-confirm'),
                onPressed: widget.onForgot,
                child: Text(l10n.passcodeForgotAction),
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

    return Scaffold(
      // Opaque by contract: this screen is the privacy barrier, so nothing of
      // the app underneath may show through.
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          const SizedBox(height: 44),
          ConsoleHexIcon(glyph: ConsoleGlyph.password, height: 56),
          Expanded(
            child: _forgotOpen
                // Replaces the entry surface instead of stacking under it:
                // the keypad plus a panel does not fit a short viewport, and
                // a recovery button below the fold is a recovery button the
                // locked-out user cannot press.
                ? Center(child: _forgotPanel(l10n, colors))
                : PasscodeEntryView(
                    mode: passcode.mode,
                    title: l10n.passcodeEnterTitle,
                    enabled: cooldown == null,
                    errorText: cooldown != null
                        ? l10n.passcodeBlocked(cooldown.inSeconds + 1)
                        : _error,
                    onSubmit: _attempt,
                    footer: TextButton(
                      key: const Key('passcode-forgot-link'),
                      onPressed: () => setState(() => _forgotOpen = true),
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
