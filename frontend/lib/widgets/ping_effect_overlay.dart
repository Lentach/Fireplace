import 'package:flutter/material.dart';

import '../utils/ping_sound.dart';

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

    _scaleAnimation = Tween<double>(begin: 0.5, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Center(
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withValues(alpha: 0.5),
                  border: Border.all(
                    color: Colors.orange,
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.campaign,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
