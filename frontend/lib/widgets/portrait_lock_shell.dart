import 'package:flutter/material.dart';

import '../utils/portrait_lock_policy.dart';
import '../utils/web_keyboard_inset.dart';
import 'portrait_required_overlay.dart';

class PortraitLockShell extends StatelessWidget {
  const PortraitLockShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // D4 fix: the keyboardVisible guard must also see the shared
    // visualViewport inset — MediaQuery.viewInsets reads 0 on iOS WebKit while
    // the keyboard is up, which made the guard inert exactly where keyboard
    // geometry can flip the reported orientation. The inactive source off iOS
    // web never fires, so this builder is free elsewhere.
    return ValueListenableBuilder<double>(
      valueListenable: sharedKeyboardInsetSource().inset,
      builder: (context, webKeyboardInset, _) {
        final mq = MediaQuery.of(context);
        final showOverlay = shouldShowRotateOverlay(
          orientation: mq.orientation,
          logicalSize: mq.size,
          keyboardVisible: mq.viewInsets.bottom > 0 || webKeyboardInset > 0,
        );
        if (!showOverlay) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            const Positioned.fill(
              child: AbsorbPointer(child: PortraitRequiredOverlay()),
            ),
          ],
        );
      },
    );
  }
}
