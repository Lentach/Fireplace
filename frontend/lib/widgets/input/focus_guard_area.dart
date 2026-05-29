import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';

import '../../utils/web_focus_guard.dart';
import '../../utils/web_ios_webkit.dart';

/// Keeps [child]'s on-screen [Rect] registered under [id] with the focus guard,
/// so an iOS-WebKit tap inside it does not blur the focused composer input
/// (which would dismiss the soft keyboard). No-op passthrough off iOS WebKit.
class FocusGuardArea extends StatefulWidget {
  const FocusGuardArea({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  /// Test-only: force the register path on the VM (where [kIsWeb] is false).
  @visibleForTesting
  static bool debugForceActiveForTest = false;

  @override
  State<FocusGuardArea> createState() => _FocusGuardAreaState();
}

class _FocusGuardAreaState extends State<FocusGuardArea> {
  bool get _active =>
      FocusGuardArea.debugForceActiveForTest || (kIsWeb && isIOSWebKit());

  void _scheduleMeasure() {
    if (!_active) return;
    // One post-frame measurement per build pass. Position only changes when the
    // composer rebuilds (keyboard inset / reply bar / action panel), so this is
    // sufficient. Do NOT re-chain inside the callback (would run every frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      registerFocusGuardRect(widget.id, rect);
    });
  }

  @override
  void dispose() {
    if (_active) unregisterFocusGuardRect(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return widget.child;
  }
}
