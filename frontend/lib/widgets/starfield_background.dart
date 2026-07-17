import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Animated starfield for the Cosmic theme — a 1:1 port of the landing hero
/// (`landing/src/scripts/util.ts` `makeStars`/`drawStars`):
///
/// - [density] stars, each `r ∈ [0.2, 1.3]px`, random phase, `speed ∈ [0.3, 1.5]`.
/// - Twinkle (dimming): `alpha = 0.22 + 0.45·|sin(phase + t·speed)|` → each star
///   breathes between 0.22 and 0.67 opacity over ~2.1–10.5s.
/// - Star tint is [starColor]; only alpha animates.
///
/// Performance gates (the animated background is the battery/jank risk):
/// - RepaintBoundary-isolated so the twinkle never repaints the chat list.
/// - One [Ticker] drives a whole-field repaint; N cheap `drawCircle`s per frame.
/// - PAUSED when off-screen: app backgrounded/tab-hidden (lifecycle) AND when
///   covered by another route (Flutter's [TickerMode] mutes the ticker).
/// - STATIC fallback (identical look, frozen at t=0) under OS reduced-motion
///   (`MediaQuery.disableAnimations`) — no ticker started at all.
///
/// Parallax from the site (`drawStars` mouse offset) is intentionally dropped:
/// it is pointer-driven and only meaningful on the desktop hero, not behind a
/// chat on the mobile-first app.
class StarfieldBackground extends StatefulWidget {
  final Color starColor;
  final int density;

  const StarfieldBackground({
    super.key,
    required this.starColor,
    this.density = 240,
  });

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Ticker _ticker;
  // Current animation time in seconds; the painter repaints on every change.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late List<_Star> _stars;
  bool _appVisible = true;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _stars = _buildStars(widget.density);
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
    WidgetsBinding.instance.addObserver(this);
  }

  static List<_Star> _buildStars(int n) {
    final rnd = math.Random(0xC05); // fixed seed: stable layout across rebuilds
    return List<_Star>.generate(n, (_) {
      return _Star(
        fx: rnd.nextDouble(),
        fy: rnd.nextDouble(),
        r: rnd.nextDouble() * 1.1 + 0.2, // 0.2–1.3px (site)
        phase: rnd.nextDouble() * (2 * math.pi),
        speed: 0.3 + rnd.nextDouble() * 1.2, // 0.3–1.5 (site)
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncTicker();
  }

  @override
  void didUpdateWidget(StarfieldBackground old) {
    super.didUpdateWidget(old);
    if (old.density != widget.density) {
      _stars = _buildStars(widget.density);
    }
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (visible != _appVisible) {
      _appVisible = visible;
      _syncTicker();
    }
  }

  /// Run the ticker only when it can be seen and motion is allowed; otherwise
  /// freeze on a static frame (t stays at its last value).
  void _syncTicker() {
    final shouldRun = _appVisible && !_reduceMotion && widget.density > 0;
    if (shouldRun) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      if (_reduceMotion) _time.value = 0; // deterministic static frame
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        isComplex: true,
        willChange: !_reduceMotion,
        painter: _StarfieldPainter(
          stars: _stars,
          color: widget.starColor,
          time: _time,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _Star {
  final double fx; // fractional x in [0,1)
  final double fy; // fractional y in [0,1)
  final double r;
  final double phase;
  final double speed;
  const _Star({
    required this.fx,
    required this.fy,
    required this.r,
    required this.phase,
    required this.speed,
  });
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> stars;
  final Color color;
  final ValueNotifier<double> time;

  _StarfieldPainter({
    required this.stars,
    required this.color,
    required this.time,
  }) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final paint = Paint()..isAntiAlias = true;
    for (final s in stars) {
      // Site formula: alpha = 0.22 + 0.45·|sin(phase + t·speed)|.
      final a = 0.22 + 0.45 * (math.sin(s.phase + t * s.speed)).abs();
      paint.color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(s.fx * size.width, s.fy * size.height), s.r, paint);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.color != color || old.stars != stars;
}
