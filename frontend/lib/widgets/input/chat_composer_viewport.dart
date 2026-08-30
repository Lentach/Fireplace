import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/keyboard_inset_math.dart';
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

class _ChatComposerViewportState extends State<ChatComposerViewport>
    with SingleTickerProviderStateMixin {
  final GlobalKey _composerKey = GlobalKey();
  double _composerHeight = 0;

  // Debounced keyboard inset: grows immediately, shrinks after 450ms.
  // Prevents layout jumping when the keyboard briefly dismisses and returns
  // (e.g. iOS PWA send-button tap bounce). The delay is longer than the iOS
  // keyboard animation (~300ms) so the layout stays stable during the bounce.
  double _keyboardInset = 0;
  Timer? _insetCollapseTimer;

  // Keyboard-dismiss ease-down (owner-approved banned-zone exception,
  // 2026-08-15): when the platform reports hide as ONE 0 event (Android PWA —
  // iOS visualViewport and native Android deliver progressive drops), the
  // composer used to teleport down a full keyboard height in one frame.
  // PAINT-ONLY by contract: layout (`_keyboardInset` → `effectiveInset`, list
  // bottom padding) still collapses in ONE frame — the immediate collapse is
  // what fixed the laggy dark gap (Symptom B); only the composer's painted
  // position eases from the old inset to 0 via Transform.translate. Never
  // tween the layout inset itself.
  late final AnimationController _dismissSlideController;
  late final CurvedAnimation _dismissSlide;
  double _dismissSlideFrom = 0;

  // iOS WebKit reports MediaQuery.viewInsets.bottom = 0 even while the keyboard
  // is up, so derive the real inset from visualViewport. Inactive (and ignored)
  // off iOS web. App-wide shared instance — never disposed here.
  late final KeyboardInsetSource _kbInsetSource;

  @override
  void initState() {
    super.initState();
    _kbInsetSource = sharedKeyboardInsetSource();
    _kbInsetSource.inset.addListener(_onKeyboardInsetChanged);
    composerBottomPanelPinned.addListener(_onBottomPanelPinnedChanged);
    _dismissSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _dismissSlide = CurvedAnimation(
      parent: _dismissSlideController,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  void _onKeyboardInsetChanged() {
    // Flutter does not rebuild on the iOS keyboard (it never sees the inset), so
    // the visualViewport listener must drive the rebuild itself.
    if (mounted) setState(() {});
  }

  void _onBottomPanelPinnedChanged() {
    // A pinned bottom panel anchors the composer at bottom: 0 regardless of
    // the inset, so a running dismiss slide would offset the pinned block.
    if (composerBottomPanelPinned.value) _cancelDismissSlide();
    if (mounted) setState(() {});
  }

  void _cancelDismissSlide() {
    if (!_dismissSlideController.isAnimating) return;
    _dismissSlideController.stop();
    _dismissSlideController.value = 1.0; // paint at the layout position
  }

  @override
  void didUpdateWidget(ChatComposerViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_measureComposer);
  }

  @override
  void dispose() {
    _insetCollapseTimer?.cancel();
    _dismissSlideController.dispose();
    composerBottomPanelPinned.removeListener(_onBottomPanelPinnedChanged);
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
    // while the keyboard is up); take the max so we never under-report.
    final raw = _kbInsetSource.isActive
        ? math.max(flutterInset, _kbInsetSource.inset.value)
        : flutterInset;

    if (raw > _keyboardInset) {
      // Keyboard growing or appearing: apply immediately, cancel any pending
      // collapse. A running dismiss slide would paint the composer above its
      // new (raised) layout position — snap it to the layout.
      _insetCollapseTimer?.cancel();
      _insetCollapseTimer = null;
      _keyboardInset = raw;
      _cancelDismissSlide();
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
        // Genuine user dismiss: collapse layout immediately so the list and
        // its padding track the keyboard down with no laggy dark gap on hide
        // (Symptom B). Only the PAINT eases: a single-step full drop to 0
        // (Android PWA reports hide as one event) starts the dismiss slide;
        // progressive dismissals (iOS visualViewport, native Android) pass
        // through small intermediate insets and never qualify.
        _insetCollapseTimer?.cancel();
        _insetCollapseTimer = null;
        final droppedFrom = _keyboardInset;
        _keyboardInset = raw;
        if (raw == 0 &&
            droppedFrom >= kMinKeyboardInset &&
            !composerBottomPanelPinned.value &&
            // A native file surface (picker sheet / OS chooser / iOS popover)
            // caused this drop — collapse silently, never ease (the surface
            // covers or dims the composer; motion behind it is the owner's
            // "input drops a little" report).
            !composerNativePickerActive.value &&
            !MediaQuery.disableAnimationsOf(context)) {
          _dismissSlideFrom = droppedFrom;
          _dismissSlideController.forward(from: 0);
        }
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
        Positioned.fill(child: widget.messageListBuilder(listBottomPadding)),
        Positioned(
          left: 0,
          right: 0,
          bottom: effectiveInset,
          // Keyboard-dismiss ease-down: layout is already at the collapsed
          // inset; while the slide runs, paint the composer up by the not-yet
          // traveled remainder of the old inset so it visually eases down.
          // Pure paint transform — never affects layout or the list padding.
          child: AnimatedBuilder(
            animation: _dismissSlide,
            builder: (context, child) {
              final remaining = (1 - _dismissSlide.value) * _dismissSlideFrom;
              if (remaining <= 0 || !_dismissSlideController.isAnimating) {
                return child!;
              }
              return Transform.translate(
                offset: Offset(0, -remaining),
                child: child,
              );
            },
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: _onComposerSizeChanged,
              child: KeyedSubtree(
                key: _composerKey,
                child: SizeChangedLayoutNotifier(child: widget.composer),
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
