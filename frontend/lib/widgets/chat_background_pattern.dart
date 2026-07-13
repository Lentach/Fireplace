import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import 'hieroglyph_glyphs.dart';

/// Chat wallpaper (owner-locked design v3.5, 2026-07-11): "temple columns" —
/// hieroglyphs stacked in vertical registers with faint column separators,
/// over the base color + a subtle radial top glow.
///
/// Layout rules (locked in the design session):
/// - columns of centered glyphs, ~3 across a phone width;
/// - weighted-random rotation, re-seeded ONCE per screen mount (owner choice:
///   a fresh arrangement every chat entry; layout is baked at construction so
///   nothing reshuffles during scrolling/repaints);
/// - no glyph repeats within the last 5 picks;
/// - never two non-wide glyphs consecutively in a column ("pen-stroke" rule);
/// - the leaf hero appears with a guaranteed cadence (~once per screen
///   height) but never twice in a row.
class ChatBackgroundPattern extends StatefulWidget {
  final Widget child;

  /// Doodle stroke color (opacity baked in). Defaults to the theme's
  /// `GlassTheme.wallpaperTint`.
  final Color? patternColor;
  final Color? backgroundColor;
  final bool enabled;

  const ChatBackgroundPattern({
    super.key,
    required this.child,
    this.patternColor,
    this.backgroundColor,
    this.enabled = true,
  });

  @override
  State<ChatBackgroundPattern> createState() => _ChatBackgroundPatternState();
}

class _ChatBackgroundPatternState extends State<ChatBackgroundPattern> {
  /// One seed per screen mount — the owner-picked "random per chat entry".
  final int _seed = math.Random().nextInt(1 << 31);

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final color = widget.patternColor ?? glass.wallpaperTint;
    final bg = widget.backgroundColor ?? Colors.transparent;
    return Container(
      color: bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.enabled)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.1),
                  radius: 1.3,
                  colors: [
                    Color.lerp(bg, color.withValues(alpha: 1.0), 0.05)!,
                    bg.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          if (widget.enabled)
            RepaintBoundary(
              child: CustomPaint(
                painter: _TempleColumnsPainter(color: color, seed: _seed),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _TempleColumnsPainter extends CustomPainter {
  final Color color;
  final int seed;

  _TempleColumnsPainter({required this.color, required this.seed});

  static const double _columnWidth = 118;
  static const double _vStep = 56;
  static const double _leafCadence = 620; // ~1 leaf per screen height

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color.withValues(alpha: (color.a * 1.15).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final sepPaint = Paint()
      ..color = color.withValues(alpha: color.a * 0.5)
      ..strokeWidth = 1;

    final rnd = math.Random(seed);
    final cols = math.max(2, (size.width / _columnWidth).round());
    final colW = size.width / cols;
    // One leaf per screen height across ALL columns (not per column): each
    // column is a parallel vertical walk, so the per-column spacing must be
    // multiplied by the column count to keep the on-screen total at ~1.
    final leafEvery = _leafCadence * cols;

    // Column separators.
    for (var i = 1; i < cols; i++) {
      canvas.drawLine(
        Offset(colW * i, 0),
        Offset(colW * i, size.height),
        sepPaint,
      );
    }

    // Bag-shuffle (owner fix for "same symbols in 3 rows"): deal every glyph
    // once before any repeats, scanning the bag for a wide glyph when the
    // previous one was narrow.
    final leaf = kHieroGlyphs.firstWhere((g) => g.isLeaf);
    var bag = <HieroGlyph>[];
    HieroGlyph deal(bool needWide) {
      if (bag.isEmpty) {
        bag = [
          for (final g in kHieroGlyphs)
            if (!g.isLeaf) g,
        ]..shuffle(rnd);
      }
      if (needWide) {
        final i = bag.indexWhere((g) => g.wide);
        if (i != -1) return bag.removeAt(i);
      }
      return bag.removeAt(0);
    }

    final cols2 = cols;
    for (var c = 0; c < cols2; c++) {
      final cx = colW * c + colW / 2;
      var y = 34 + rnd.nextDouble() * 12;
      var sinceLeaf = rnd.nextDouble() * leafEvery;
      var prevNarrow = false;
      while (y < size.height - 18) {
        HieroGlyph g;
        if (sinceLeaf > leafEvery) {
          g = leaf;
          sinceLeaf = 0;
        } else {
          g = deal(prevNarrow);
        }
        prevNarrow = g.wide == false;

        final scale = 0.85 + rnd.nextDouble() * 0.15;
        canvas.save();
        canvas.translate(cx, y);
        canvas.scale(scale);
        g.paintFn(canvas, stroke, fill);
        canvas.restore();

        final step = _vStep + (rnd.nextDouble() * 10 - 4);
        y += step;
        sinceLeaf += step;
      }
    }
  }

  @override
  bool shouldRepaint(_TempleColumnsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}
