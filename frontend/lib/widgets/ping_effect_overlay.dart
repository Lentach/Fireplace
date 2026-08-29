import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/ping_sound.dart';
import 'hex_avatar.dart';
import 'ping_glyph.dart';

class PingEffectOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const PingEffectOverlay({super.key, required this.onComplete});

  @override
  State<PingEffectOverlay> createState() => _PingEffectOverlayState();
}

class _PingEffectOverlayState extends State<PingEffectOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  bool _completed = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    // Fire-and-forget: on web this plays through the Web Audio API (no
    // MediaSession ⇒ no stale iOS media-control card); on native via just_audio.
    playPingSound().ignore();
    _controller.forward().then((_) {
      if (mounted) {
        _completed = true;
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    // Route popped mid-animation: the forward().then above never fires its
    // callback (unmounted), so without this the showPingEffect flag stays
    // latched and the NEXT chat entry remounts the overlay and replays the
    // sound (same-session replay; the per-id decrypt guard cannot help — the
    // flag is already true). Defer past teardown: a sync notifyListeners here
    // would fire an ancestor setState during tree finalization (same trap as
    // the composerBottomPanelPinned dispose reset).
    if (!_completed) {
      scheduleMicrotask(widget.onComplete);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Static subtree: built ONCE (this build runs once — no setState/AnimatedBuilder
    // rebuild loop). The transitions below drive opacity/scale straight off the
    // controller without rebuilding this subtree per frame; both hex painters and
    // the CustomPaint glyph are created once rather than per frame.
    final badge = SizedBox.square(
      dimension: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The orange below is deliberately NOT a theme token, and not a
          // §9 violation: the ping is an attention signal that must read the
          // same on all five themes and must never be mistaken for the error
          // red or for a theme's own primary (which is red on Ember). Alpha is
          // baked per ring so this whole badge stays `const` for the
          // RepaintBoundary fast path below.
          // Concentric hex lattice, not circles: the ping propagates in the
          // app's own shape language (owner ask 2026-08-03).
          const SizedBox(
            width: 112 * kHexWidthRatio,
            height: 112,
            child: CustomPaint(
              painter: _PingHexPainter(
                border: Color(0x47FF9800), // orange, alpha 0.28
                strokeWidth: 1.5,
              ),
            ),
          ),
          const SizedBox(
            width: 96 * kHexWidthRatio,
            height: 96,
            child: CustomPaint(
              painter: _PingHexPainter(
                fill: Color(0x29FF9800), // orange, alpha 0.16
                border: Color(0xE0FF9800), // orange, alpha 0.88
                strokeWidth: 2.5,
              ),
            ),
          ),
          const PingGlyph(size: 50, color: Colors.white),
        ],
      ),
    );
    // RepaintBoundary: this overlay is Positioned.fill inside the chat Stack, so
    // the 800ms animation must not mark the message list dirty. FadeTransition
    // (no per-frame Opacity saveLayer) + ScaleTransition animate the cached child.
    return RepaintBoundary(
      child: Center(
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: ScaleTransition(scale: _scaleAnimation, child: badge),
        ),
      ),
    );
  }
}

/// One static pointy-top hex ring of the ping lattice: optional fill plus a
/// stroked `hexPath` outline. Constructed const so the ping subtree stays a
/// build-once cached child under the Fade/Scale transitions.
class _PingHexPainter extends CustomPainter {
  const _PingHexPainter({
    this.fill,
    required this.border,
    required this.strokeWidth,
  });

  final Color? fill;
  final Color border;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final path = hexPath(c, size.height / 2 - strokeWidth / 2);
    if (fill != null) {
      canvas.drawPath(path, Paint()..color = fill!);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(covariant _PingHexPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.strokeWidth != strokeWidth;
}
