import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/rpg_theme.dart';
import 'hex_avatar.dart';

/// Row grammar for the Settings "local node console".
///
/// Settings used to be a Material list of tinted glass cards with stock
/// `Icons.*` glyphs and a chevron on every row — the one tab that did not look
/// like the rest of the app. This kit gives it the SAME grammar Chats and the
/// Contacts classic list already use: a 44px hex at left offset 12, a 12px
/// gap, opaque rows, no dividers, no chevrons. The affordance is the row.
///
/// The glyphs inside the hexes are drawn here rather than taken from the
/// Material set (owner call, 2026-07-25): a stock shield or laptop icon inside
/// our hex frame was the last "different app" tell. They share one stroke spec
/// so the set reads as instrument line-work, not as clip art.

/// Leading hex width follows the pointy-top ratio, like every other hex.
const double kConsoleHexHeight = 44;
const double kConsoleHexLeft = 12;
const double kConsoleRowMinHeight = 64;
double get kConsoleHexWidth => kConsoleHexHeight * kHexWidthRatio;

/// How a row is marked as consequential. `danger` is destructive (delete),
/// `accent` is a state change worth pausing on (log out). Both reuse the lit
/// row edge the Chats list already uses for unread.
enum ConsoleRowEdge { none, danger, accent }

/// The drawn glyph set. Keep these geometric and single-weight.
enum ConsoleGlyph {
  palette,
  globe,
  shield,
  blocked,
  device,
  signal,
  key,
  nodeX,
  exit,
}

/// Section header. Type copied from the already-shipped Appearance sub-screen
/// (`appearance_screen.dart`) so the Settings root and the screen it opens do
/// not speak two dialects.
class SettingsSectionCaption extends StatelessWidget {
  const SettingsSectionCaption({super.key, required this.label});

  final String label;

  static TextStyle styleOf(BuildContext context) => RpgTheme.bodyFont(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ).copyWith(letterSpacing: 1.1);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kConsoleHexLeft, 18, 16, 8),
      child: Row(
        children: [
          Text(label, style: styleOf(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: colorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsConsoleRow extends StatelessWidget {
  const SettingsConsoleRow({
    super.key,
    required this.glyph,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.edge = ConsoleRowEdge.none,
    this.leadingOverride,
  });

  final ConsoleGlyph glyph;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final ConsoleRowEdge edge;

  /// Replaces the glyph inside the hex — used by the Appearance row, whose
  /// "icon" is really a live preview of the current theme.
  final Widget? leadingOverride;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final edgeColor = switch (edge) {
      ConsoleRowEdge.danger => colorScheme.error,
      ConsoleRowEdge.accent => colorScheme.primary,
      ConsoleRowEdge.none => null,
    };

    final row = Container(
      constraints: const BoxConstraints(minHeight: kConsoleRowMinHeight),
      // Only the DESTRUCTIVE row gets the filled wash. Logging out is not
      // dangerous, and on the light themes `primary` is nearly the same ember
      // as `error`, so washing both made Delete Account and Log out merge
      // into one continuous alarm block. Edge-only keeps them separate.
      decoration: edgeColor == null
          ? null
          : BoxDecoration(
              color: edge == ConsoleRowEdge.danger
                  ? edgeColor.withValues(alpha: 0.05)
                  : null,
              border: Border(left: BorderSide(color: edgeColor, width: 3)),
            ),
      child: Row(
        children: [
          // The 3px lit edge eats into the gutter so the hex column stays on
          // the same axis as every other row.
          SizedBox(
            width: edgeColor == null ? kConsoleHexLeft : kConsoleHexLeft - 3,
          ),
          ConsoleHexIcon(glyph: glyph, tint: edgeColor, child: leadingOverride),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: edgeColor ?? colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: RpgTheme.bodyFont(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
          const SizedBox(width: 16),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// The hex terminal that holds a glyph. Same ink and weight as the board's
/// `_HexChromePainter`: one outline, nothing inside it.
class ConsoleHexIcon extends StatelessWidget {
  const ConsoleHexIcon({super.key, required this.glyph, this.tint, this.child});

  final ConsoleGlyph glyph;
  final Color? tint;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    final ink = tint ?? colorScheme.primary;

    return SizedBox(
      width: kConsoleHexWidth,
      height: kConsoleHexHeight,
      child: CustomPaint(
        foregroundPainter: _HexOutlinePainter(
          color: tint ?? colorScheme.onSurface,
          alpha: tint == null ? 0.42 : 0.75,
        ),
        child: ClipPath(
          clipper: const HexClipper(),
          child:
              child ??
              ColoredBox(
                color: colors.convItemBg,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CustomPaint(
                      painter: ConsoleGlyphPainter(glyph: glyph, color: ink),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

class _HexOutlinePainter extends CustomPainter {
  const _HexOutlinePainter({required this.color, required this.alpha});

  final Color color;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      hexPath(size.center(Offset.zero), size.height / 2 - 0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _HexOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.alpha != alpha;
}

/// One stroke spec for every glyph: 1.6 wide, round caps and joins, drawn in a
/// 24-unit design space and scaled to whatever box it is given. Single weight
/// is what makes a hand-drawn set look deliberate instead of homemade.
class ConsoleGlyphPainter extends CustomPainter {
  const ConsoleGlyphPainter({required this.glyph, required this.color});

  final ConsoleGlyph glyph;
  final Color color;

  static const double _unit = 24;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _unit, size.height / _unit);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (glyph) {
      case ConsoleGlyph.palette:
        canvas.drawCircle(const Offset(12, 12), 8, stroke);
        for (final a in [-2.2, -1.4, -0.6]) {
          canvas.drawCircle(
            Offset(12 + 4.4 * math.cos(a), 12 + 4.4 * math.sin(a)),
            1.3,
            stroke,
          );
        }
      case ConsoleGlyph.globe:
        canvas.drawCircle(const Offset(12, 12), 7.8, stroke);
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(12, 12),
            width: 7.6,
            height: 15.6,
          ),
          stroke,
        );
        canvas.drawLine(const Offset(4.2, 12), const Offset(19.8, 12), stroke);
      case ConsoleGlyph.shield:
        canvas.drawPath(
          Path()
            ..moveTo(12, 3.4)
            ..lineTo(19.4, 6.8)
            ..lineTo(19.4, 12)
            ..lineTo(12, 20.6)
            ..lineTo(4.6, 12)
            ..lineTo(4.6, 6.8)
            ..close(),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8.8, 11.8)
            ..lineTo(11.1, 14.1)
            ..lineTo(15.2, 9.6),
          stroke,
        );
      case ConsoleGlyph.blocked:
        canvas.drawCircle(const Offset(12, 12), 7.6, stroke);
        canvas.drawLine(
          const Offset(6.6, 6.6),
          const Offset(17.4, 17.4),
          stroke,
        );
      case ConsoleGlyph.device:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(3.6, 5.4, 20.4, 15.6),
            const Radius.circular(1.6),
          ),
          stroke,
        );
        canvas.drawLine(const Offset(12, 15.6), const Offset(12, 18.8), stroke);
        canvas.drawLine(
          const Offset(8.4, 18.8),
          const Offset(15.6, 18.8),
          stroke,
        );
      case ConsoleGlyph.signal:
        canvas.drawCircle(const Offset(12, 17.4), 1.5, Paint()..color = color);
        for (final r in [5.2, 9.0]) {
          canvas.drawArc(
            Rect.fromCircle(center: const Offset(12, 17.4), radius: r),
            math.pi * 1.18,
            math.pi * 0.64,
            false,
            stroke,
          );
        }
      case ConsoleGlyph.key:
        canvas.drawCircle(const Offset(7.6, 12), 3.4, stroke);
        canvas.drawLine(const Offset(11, 12), const Offset(20, 12), stroke);
        canvas.drawLine(
          const Offset(16.6, 12),
          const Offset(16.6, 15.2),
          stroke,
        );
        canvas.drawLine(
          const Offset(19.4, 12),
          const Offset(19.4, 14.2),
          stroke,
        );
      case ConsoleGlyph.nodeX:
        canvas.drawPath(hexPath(const Offset(12, 12), 8.4), stroke);
        canvas.drawLine(
          const Offset(9.2, 9.2),
          const Offset(14.8, 14.8),
          stroke,
        );
        canvas.drawLine(
          const Offset(14.8, 9.2),
          const Offset(9.2, 14.8),
          stroke,
        );
      case ConsoleGlyph.exit:
        canvas.drawPath(
          Path()
            ..moveTo(13.4, 4.6)
            ..lineTo(5.4, 4.6)
            ..lineTo(5.4, 19.4)
            ..lineTo(13.4, 19.4),
          stroke,
        );
        canvas.drawLine(const Offset(10.6, 12), const Offset(19.6, 12), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(16.6, 9)
            ..lineTo(19.6, 12)
            ..lineTo(16.6, 15),
          stroke,
        );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ConsoleGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
