import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  @override
  void didUpdateWidget(ChatComposerViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  @override
  void dispose() {
    _insetCollapseTimer?.cancel();
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
    final raw = MediaQuery.viewInsetsOf(context).bottom;

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
        if (ComposerDiagnosticsOverlay.isEnabled)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            left: 8,
            child: ComposerDiagnosticsOverlay(debouncedInset: _keyboardInset),
          ),
      ],
    );
  }
}
