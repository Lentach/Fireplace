import 'package:flutter/material.dart';

import '../utils/portrait_lock_policy.dart';
import 'portrait_required_overlay.dart';

class PortraitLockShell extends StatelessWidget {
  const PortraitLockShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final showOverlay = shouldShowRotateOverlay(
      orientation: mq.orientation,
      logicalSize: mq.size,
      keyboardVisible: mq.viewInsets.bottom > 0,
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
  }
}
