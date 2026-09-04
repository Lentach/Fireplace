import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/passcode_provider.dart';
import '../screens/passcode_unlock_screen.dart';
import '../services/local_data_eraser.dart';

/// Wraps the whole app below `MaterialApp.builder`, so the lock covers every
/// pushed route and the bottom nav — not just the shell.
///
/// The guarded subtree is hidden with [Offstage], never unmounted: tearing
/// down `MainShell` would drop the socket, the active conversation and any
/// in-flight send, and this app's reconnect path is where its worst field bugs
/// have lived. Offstage skips paint, hit-testing and semantics, so the content
/// is unreachable while its state stays intact.
class PasscodeGate extends StatelessWidget {
  const PasscodeGate({super.key, required this.child, LocalDataEraser? eraser})
    : _eraser = eraser;

  final Widget child;

  /// Injectable so widget tests can prove the destructive path runs without
  /// wiping the test host's own stores.
  final LocalDataEraser? _eraser;

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
                : PasscodeUnlockScreen(onErase: () => _erase(context)),
          ),
      ],
    );
  }

  /// The only way past a forgotten code (owner ruling 2026-09-04): destroy
  /// every local store, then sign out.
  ///
  /// Order matters. The eraser clears the passcode flag before the credential
  /// (see `services/local_data_eraser.dart`), then the provider re-reads the
  /// now-empty store so the gate opens, and only then does the logout run —
  /// a failing logout must not leave the user staring at a lock screen they
  /// already told us they cannot satisfy.
  Future<LocalDataEraseReport> _erase(BuildContext context) async {
    final passcode = context.read<PasscodeProvider>();
    final auth = context.read<AuthProvider>();
    final report = await (_eraser ?? DeviceLocalDataEraser()).eraseEverything();
    await passcode.initialize();
    await auth.logout();
    return report;
  }
}
