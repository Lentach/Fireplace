import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

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
  AudioPlayer? _audioPlayer;

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

    _playPingSound();
    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  Future<void> _playPingSound() async {
    final player = AudioPlayer();
    _audioPlayer = player;
    try {
      await player.setAsset('assets/sounds/ping_alert.mp3');
      await player.play();
      await player.processingStateStream.firstWhere(
        (s) => s == ProcessingState.completed,
      );
    } catch (e) {
      debugPrint('Error playing ping sound: $e');
    } finally {
      if (identical(_audioPlayer, player)) {
        _audioPlayer = null;
      }
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    final player = _audioPlayer;
    _audioPlayer = null;
    if (player != null) {
      player.dispose().catchError((_) {});
    }
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
