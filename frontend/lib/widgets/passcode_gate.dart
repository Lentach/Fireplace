import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/passcode_provider.dart';
import '../screens/passcode_unlock_screen.dart';
import '../services/local_data_eraser.dart';
import '../utils/privacy_curtain.dart';
import 'input/composer_keyboard_signals.dart';
import 'passcode_curtain.dart';

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
    final passcode = context.watch<PasscodeProvider>();
    return ValueListenableBuilder<bool>(
      valueListenable: composerNativePickerActive,
      builder: (context, pickerActive, _) => _body(context, passcode, pickerActive),
    );
  }

  Widget _body(BuildContext context, PasscodeProvider passcode, bool pickerActive) {
    final state = passcode.state;
    // `unknown` counts as covered: the credential has not been read yet, and
    // painting the shell for one frame on every cold start of a locked app
    // would defeat the point.
    final covered =
        state == PasscodeLockState.locked || state == PasscodeLockState.unknown;
    // The curtain is painted OVER the app rather than Offstage-ing it: the
    // subtree may hold a pending `<input type=file>` (the attach picker), and
    // un-painting it mid-pick is the (2026-08-21) lost-pick shape again.
    final curtained = !covered && passcode.curtained;

    // The DOM curtain (web/index.html) is shown by the page itself on blur —
    // no Flutter frame needed — and at boot when a passcode is enabled. It is
    // lifted HERE, after a frame that paints the state replacing it: the lock
    // screen, or the app once the return verdict said "still inside the
    // window". Lifting any earlier is the chat-for-one-frame flash again.
    // Disarmed for the attach picker span (`composerNativePickerActive`): the
    // OS sheet hides the page, and a curtain over the composer would flash
    // when it closes — the same exemption the immediate lock has.
    armDomCurtain(passcode.isEnabled && !pickerActive);
    if (state != PasscodeLockState.unknown && !curtained) {
      WidgetsBinding.instance.addPostFrameCallback((_) => hideDomCurtain());
    }
    return Stack(
      children: [
        Positioned.fill(child: Offstage(offstage: covered, child: child)),
        if (covered)
          Positioned.fill(
            child: state == PasscodeLockState.unknown
                ? const PasscodeCurtain()
                : PasscodeUnlockScreen(onErase: () => _erase(context)),
          ),
        if (curtained) const Positioned.fill(child: PasscodeCurtain()),
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
