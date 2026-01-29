import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
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
        final visible = _controller.value < 0.5;
        return Opacity(
          opacity: visible ? 1.0 : 0.0,
          child: Text(
            '_',
            style: RpgTheme.pressStart2P(
              fontSize: 8,
              color: RpgTheme.headerGreen,
            ),
          ),
        );
      },
    );
  }
}
