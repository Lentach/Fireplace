import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';

import '../../utils/web_focus_guard.dart';
import '../../utils/web_ios_webkit.dart';
import '../../utils/web_keyboard_inset.dart';

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

  // Cached so dispose removes the listener from the SAME instance initState
  // added it to (mirrors ChatInputBar's _sharedInsetSource caching).
  KeyboardInsetSource? _insetSource;
  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    if (!_active) return;
    // The composer MOVES without this subtree rebuilding while the iOS
    // keyboard pans: ChatComposerViewport repositions `Positioned(bottom:)`
    // per visualViewport event, but its `composer` child is an identical
    // widget instance (rebuild skipped), and ChatInputBar's own rebuild is
    // gated on the inset BOOLEAN (H2). A rect measured at pan start would be
    // stranded ~300px under the settled composer and the load-bearing guard
    // would miss — every first tap after a keyboard rise would blur (the
    // FG-OFF catastrophe). Re-measure per inset event instead: post-frame so
    // the reposition has landed, registration only (no setState, no rebuild).
    _insetSource = sharedKeyboardInsetSource();
    _insetSource!.inset.addListener(_scheduleMeasure);
  }

  void _scheduleMeasure() {
    if (!_active || _measureScheduled) return;
    // One post-frame measurement per frame. Builds and inset events can both
    // request it; the flag dedupes. Do NOT re-chain inside the callback
    // (would run every frame).
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      registerFocusGuardRect(widget.id, rect);
    });
  }

  @override
  void dispose() {
    _insetSource?.inset.removeListener(_scheduleMeasure);
    if (_active) unregisterFocusGuardRect(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_active) _scheduleMeasure();
    return widget.child;
  }
}
