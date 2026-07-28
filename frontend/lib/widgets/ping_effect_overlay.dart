import 'package:flutter/material.dart';

import '../utils/ping_sound.dart';
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
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Static subtree: built ONCE (this build runs once — no setState/AnimatedBuilder
    // rebuild loop). The transitions below drive opacity/scale straight off the
    // controller without rebuilding this subtree per frame, and the CustomPaint
    // glyph is created once rather than per frame.
    final badge = SizedBox.square(
      dimension: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.28),
                width: 1.5,
              ),
            ),
          ),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orange.withValues(alpha: 0.16),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.88),
                width: 2.5,
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
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: badge,
          ),
        ),
      ),
    );
  }
}
