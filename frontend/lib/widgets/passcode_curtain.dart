import 'package:flutter/material.dart';

import 'settings_console.dart';

/// The lock screen's chrome with nothing to type: an opaque cover.
///
/// Painted by [PasscodeGate] in two moments that used to show something
/// worse. Before the credential read resolves on boot it replaces a bare
/// scaffold-coloured box — the "white" the owner saw between the chat and the
/// lock screen on a wake-lock. And from the first departure signal until the
/// return verdict it covers the app, so the frame the browser re-shows on
/// wake is this and not the chat.
///
/// Same background, same glyph, same top offset as [PasscodeUnlockScreen], so
/// a curtain that becomes a lock screen does not visibly move.
class PasscodeCurtain extends StatelessWidget {
  const PasscodeCurtain({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('passcode-curtain'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const Column(
        children: [
          SizedBox(height: 44),
          ConsoleHexIcon(glyph: ConsoleGlyph.password, height: 56),
        ],
      ),
    );
  }
}
