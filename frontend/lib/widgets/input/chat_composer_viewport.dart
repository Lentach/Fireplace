import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/web_keyboard_inset.dart';
import 'composer_diagnostics_overlay.dart';
import 'composer_keyboard_signals.dart';

/// Builds the scrollable message list with [listBottomPadding] clearance for the
/// overlaid composer and keyboard inset.
typedef MessageListBuilder = Widget Function(double listBottomPadding);

/// Owns chat layout: messages fill the stack; [composer] is positioned at the
/// bottom above the keyboard inset. The inset comes from `visualViewport` on iOS
/// WebKit (where `MediaQuery.viewInsets.bottom` reads 0 while the keyboard is up)
/// and from [MediaQuery.viewInsets] everywhere else — see
/// `utils/web_keyboard_inset.dart`. List bottom padding tracks measured composer
/// height plus that inset so [Expanded] does not shrink when the composer grows
/// (reply bar, action panel).
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
  // off iOS web. App-wide shared instance — never disposed here.
  late final KeyboardInsetSource _kbInsetSource;

  @override
  void initState() {
    super.initState();
    _kbInsetSource = sharedKeyboardInsetSource();
    _kbInsetSource.inset.addListener(_onKeyboardInsetChanged);
    predictedComposerKeyboardInset.addListener(_onKeyboardInsetChanged);
    composerBottomPanelPinned.addListener(_onBottomPanelPinnedChanged);
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  void _onKeyboardInsetChanged() {
    // Flutter does not rebuild on the iOS keyboard (it never sees the inset), so
    // the visualViewport listener must drive the rebuild itself.
    if (mounted) setState(() {});
  }

  void _onBottomPanelPinnedChanged() {
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
    composerBottomPanelPinned.removeListener(_onBottomPanelPinnedChanged);
    predictedComposerKeyboardInset.removeListener(_onKeyboardInsetChanged);
    _kbInsetSource.inset.removeListener(_onKeyboardInsetChanged);
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
    // while the keyboard is up); take the max so we never under-report. The
    // predicted inset (flash-fix pointer-down pre-arm, 0 when idle) folds in
    // the same way: the grow branch below applies it immediately, and the
    // real-inset handoff / safety clear in ChatInputBar releases it.
    final base = _kbInsetSource.isActive
        ? math.max(flutterInset, _kbInsetSource.inset.value)
        : flutterInset;
    final raw = math.max(base, predictedComposerKeyboardInset.value);

    if (raw > _keyboardInset) {
      // Keyboard growing or appearing: apply immediately, cancel any pending collapse.
      _insetCollapseTimer?.cancel();
      _insetCollapseTimer = null;
      _keyboardInset = raw;
    } else if (raw < _keyboardInset) {
      if (composerKeyboardCollapseGuard.value) {
        // A send / refocus is in flight: the keyboard may bounce straight back
        // (iOS send-button), so wait 450ms before collapsing layout to avoid a
        // visible composer drop + black-screen flash. If the keyboard returns
        // within the window the grow branch above re-applies raw immediately.
        _insetCollapseTimer ??= Timer(const Duration(milliseconds: 450), () {
          _insetCollapseTimer = null;
          if (mounted) setState(() => _keyboardInset = 0);
        });
      } else {
        // Genuine user dismiss: collapse immediately so the composer tracks the
        // keyboard down with no laggy dark gap on hide (Symptom B).
        _insetCollapseTimer?.cancel();
        _insetCollapseTimer = null;
        _keyboardInset = raw;
      }
    }

    // NOTE: this block intentionally mutates debounce state (`_keyboardInset`,
    // `_insetCollapseTimer`) during build. It is safe because the grow branch is
    // idempotent, the collapse is guarded by `_insetCollapseTimer == null`, and
    // `_keyboardInset` is re-derived from the live `raw` on every build. Bounce
    // self-corrects: the collapse timer's setState rebuilds, and if the keyboard
    // is still up `raw` re-grows `_keyboardInset` in the same frame (no visible
    // drop). Keep `raw` sourced live so this invariant holds.
    // While a composer bottom panel (emoji picker) is open it REPLACES the
    // keyboard: anchor the composer block at the true bottom so the panel sits
    // in the keyboard's space from the first frame and a dismissing keyboard
    // simply reveals it. Without the pin the block hovers at the stale inset
    // (input row near the top of the screen) and visibly drops as the inset
    // collapses. _keyboardInset keeps tracking raw for when the pin releases
    // (tapping the field closes the panel and reopens the keyboard).
    final effectiveInset = composerBottomPanelPinned.value
        ? 0.0
        : _keyboardInset;
    final listBottomPadding = _composerHeight + effectiveInset;

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
          bottom: effectiveInset,
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
