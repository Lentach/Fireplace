import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/web_keyboard_inset.dart';
import 'composer_diagnostics_overlay.dart';

/// Builds the scrollable message list with [listBottomPadding] clearance for the
/// overlaid composer and keyboard inset.
typedef MessageListBuilder = Widget Function(double listBottomPadding);

/// Owns chat layout: messages fill the stack; [composer] is positioned at the
/// bottom above [MediaQuery.viewInsets]. List bottom padding tracks measured
/// composer height plus keyboard inset so [Expanded] does not shrink when the
/// composer grows (reply bar, action panel).
class ChatComposerViewport extends StatefulWidget {
  const ChatComposerViewport({
    super.key,
    required this.messageListBuilder,
    required this.composer,
  });

  final MessageListBuilder messageListBuilder;
  final Widget composer;

  @override
  State<ChatComposerViewport> createState() => _ChatComposerViewportState();
}

class _ChatComposerViewportState extends State<ChatComposerViewport> {
  final GlobalKey _composerKey = GlobalKey();
  double _composerHeight = 0;

  // Debounced keyboard inset: grows immediately, shrinks after 450ms.
  // Prevents layout jumping when the keyboard briefly dismisses and returns
  // (e.g. iOS PWA send-button tap bounce). The delay is longer than the iOS
  // keyboard animation (~300ms) so the layout stays stable during the bounce.
  double _keyboardInset = 0;
  Timer? _insetCollapseTimer;

  // iOS WebKit reports MediaQuery.viewInsets.bottom = 0 even while the keyboard
  // is up, so derive the real inset from visualViewport. Inactive (and ignored)
  // off iOS web.
  late final KeyboardInsetSource _kbInsetSource;

  @override
  void initState() {
    super.initState();
    _kbInsetSource = createKeyboardInsetSource();
    _kbInsetSource.inset.addListener(_onKeyboardInsetChanged);
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  void _onKeyboardInsetChanged() {
    // Flutter does not rebuild on the iOS keyboard (it never sees the inset), so
    // the visualViewport listener must drive the rebuild itself.
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ChatComposerViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  @override
  void dispose() {
    _insetCollapseTimer?.cancel();
    _kbInsetSource.inset.removeListener(_onKeyboardInsetChanged);
    _kbInsetSource.dispose();
    super.dispose();
  }

  void _measureComposer([Duration? _]) {
    if (!mounted) return;
    final renderObject = _composerKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final height = renderObject.size.height;
    if (height != _composerHeight) {
      setState(() => _composerHeight = height);
    }
  }

  bool _onComposerSizeChanged(SizeChangedLayoutNotification notification) {
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final flutterInset = MediaQuery.viewInsetsOf(context).bottom;
    // On iOS WebKit prefer the visualViewport-derived inset (Flutter's reads 0
    // while the keyboard is up); take the max so we never under-report.
    final raw = _kbInsetSource.isActive
        ? math.max(flutterInset, _kbInsetSource.inset.value)
        : flutterInset;

    if (raw > _keyboardInset) {
      // Keyboard growing or appearing: apply immediately, cancel any pending collapse.
      _insetCollapseTimer?.cancel();
      _insetCollapseTimer = null;
      _keyboardInset = raw;
    } else if (raw < _keyboardInset && _insetCollapseTimer == null) {
      // Keyboard shrinking: wait 450ms before collapsing layout.
      // If the keyboard bounces back within that window the timer is cancelled
      // (next build with raw > _keyboardInset hits the branch above).
      _insetCollapseTimer = Timer(const Duration(milliseconds: 450), () {
        _insetCollapseTimer = null;
        if (mounted) setState(() => _keyboardInset = 0);
      });
    }

    final listBottomPadding = _composerHeight + _keyboardInset;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: widget.messageListBuilder(listBottomPadding),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: _keyboardInset,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: _onComposerSizeChanged,
            child: KeyedSubtree(
              key: _composerKey,
              child: SizeChangedLayoutNotifier(
                child: widget.composer,
              ),
            ),
          ),
        ),
        if (ComposerDiagnosticsOverlay.isAvailable)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            left: 8,
            child: ValueListenableBuilder<bool>(
              valueListenable: composerDiagOverlayEnabled,
              builder: (context, enabled, _) => enabled
                  ? ComposerDiagnosticsOverlay(
                      flutterInset: flutterInset,
                      computedInset: _kbInsetSource.isActive
                          ? _kbInsetSource.inset.value
                          : null,
                      debouncedInset: _keyboardInset,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}
