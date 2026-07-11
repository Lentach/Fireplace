import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// zengi-style progressive fade under the floating chat top chrome (owner
/// ruling 2026-07-11): content sliding under the title zone blurs and dims,
/// keeping the contact name dominant. Two stacked static blur strips
/// approximate a progressive blur; a scaffold-tinted gradient does the dim.
/// Pure paint — [IgnorePointer] keeps scrolling/hit-testing untouched.
class ChatTopFade extends StatelessWidget {
  const ChatTopFade({super.key});

  /// Chrome footprint the fade must cover (GlassTopBar height incl. inset).
  static const double _chromeBand = 68;

  /// Soft falloff below the chrome.
  static const double _falloff = 34;

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.viewPaddingOf(context).top;
    final strong = statusBar + _chromeBand;
    final total = strong + _falloff;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: total,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft outer blur across the whole band.
            ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const SizedBox.expand(),
              ),
            ),
            // Stronger blur where the chrome actually sits.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: strong,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // Dimming gradient: heavy at the very top, gone at the tail.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bg.withValues(alpha: 0.88),
                    bg.withValues(alpha: 0.55),
                    bg.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
