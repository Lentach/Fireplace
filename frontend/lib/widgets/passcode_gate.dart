import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/passcode_provider.dart';
import '../screens/passcode_unlock_screen.dart';

/// Wraps the whole app below `MaterialApp.builder`, so the lock covers every
/// pushed route and the bottom nav — not just the shell.
///
/// The guarded subtree is hidden with [Offstage], never unmounted: tearing
/// down `MainShell` would drop the socket, the active conversation and any
/// in-flight send, and this app's reconnect path is where its worst field bugs
/// have lived. Offstage skips paint, hit-testing and semantics, so the content
/// is unreachable while its state stays intact.
class PasscodeGate extends StatelessWidget {
  const PasscodeGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PasscodeProvider>().state;
    // `unknown` counts as covered: the credential has not been read yet, and
    // painting the shell for one frame on every cold start of a locked app
    // would defeat the point.
    final covered =
        state == PasscodeLockState.locked || state == PasscodeLockState.unknown;

    return Stack(
      children: [
        Positioned.fill(child: Offstage(offstage: covered, child: child)),
        if (covered)
          Positioned.fill(
            child: state == PasscodeLockState.unknown
                ? ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)
                : PasscodeUnlockScreen(onForgot: () => _forgot(context)),
          ),
      ],
    );
  }

  /// Owner ruling 2026-09-03: a forgotten passcode costs a logout, never
  /// history. Order matters — clear the credential FIRST, so a failure in the
  /// logout call cannot leave the user staring at a lock screen they already
  /// told us they cannot satisfy. Signal keys survive logout (root CLAUDE.md
  /// §6), so every message comes back after signing in again.
  static Future<void> _forgot(BuildContext context) async {
    final passcode = context.read<PasscodeProvider>();
    final auth = context.read<AuthProvider>();
    await passcode.clearForRecovery();
    await auth.logout();
  }
}
