import 'package:flutter/material.dart';

import '../theme/rpg_theme.dart';
import 'console_glyphs.dart';
import 'hex_avatar.dart';

/// Row grammar for the Settings "local node console".
///
/// Settings used to be a Material list of tinted glass cards with stock
/// `Icons.*` glyphs and a chevron on every row — the one tab that did not look
/// like the rest of the app. This kit gives it the SAME grammar Chats and the
/// Contacts classic list already use: a 44px hex at left offset 12, a 12px
/// gap, opaque rows, no dividers, no chevrons. The affordance is the row.
///
/// The glyphs live in `console_glyphs.dart` and are re-exported here so a
/// screen needs one import to build a console.
export 'console_glyphs.dart' show ConsoleGlyph, ConsoleGlyphSet;

/// Leading hex width follows the pointy-top ratio, like every other hex.
const double kConsoleHexHeight = 44;
const double kConsoleHexLeft = 12;
const double kConsoleRowMinHeight = 64;
double get kConsoleHexWidth => kConsoleHexHeight * kHexWidthRatio;

/// How a row is marked as consequential. `danger` is destructive (delete),
/// `accent` is a state change worth pausing on (log out). Both reuse the lit
/// row edge the Chats list already uses for unread.
enum ConsoleRowEdge { none, danger, accent }

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
          // Upper-cased HERE, not by the caller. Some captions come from
          // section keys that are already caps (`SECURITY`) and others reuse
          // a screen title that is not (`Privacy & Safety`), which put three
          // different casings on one rail in the Privacy screen. Normalising
          // at the widget means no call site can break the rail again.
          Text(label.toUpperCase(), style: styleOf(context)),
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
    this.set = ConsoleGlyphSet.instrument,
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

  /// Which glyph drawing to use. Exists only while the owner is choosing
  /// between the two sets; it goes when the losing set is deleted.
  final ConsoleGlyphSet set;

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
          ConsoleHexIcon(
            glyph: glyph,
            tint: edgeColor,
            set: set,
            child: leadingOverride,
          ),
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

/// A row that explains rather than navigates: hex terminal, title, and a body
/// paragraph with no line clamp.
///
/// This is what the Privacy & Safety screen's translucent Material cards
/// became. They were a double violation — a tinted card is the Material
/// settings-list tell the console removed, and `SPEC.md` §1 forbids
/// translucency behind body text outright. The information is the same; only
/// the card is gone.
class ConsoleInfoRow extends StatelessWidget {
  const ConsoleInfoRow({
    super.key,
    required this.glyph,
    required this.title,
    required this.body,
  });

  final ConsoleGlyph glyph;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: title,
      value: body,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: kConsoleHexLeft),
            // Top-aligned: a paragraph row is tall, and a vertically centred
            // terminal would float away from the title it belongs to.
            ConsoleHexIcon(glyph: glyph),
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
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: RpgTheme.bodyFont(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ).copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// The hex terminal that holds a glyph. Same ink and weight as the board's
/// `_HexChromePainter`: one outline, nothing inside it.
class ConsoleHexIcon extends StatelessWidget {
  const ConsoleHexIcon({
    super.key,
    required this.glyph,
    this.tint,
    this.child,
    this.height = kConsoleHexHeight,
    this.set = ConsoleGlyphSet.instrument,
  });

  final ConsoleGlyph glyph;
  final Color? tint;
  final Widget? child;

  /// Terminal height. The glyph scales with it, so a screen header can use
  /// the same widget at 64–72px instead of hand-rolling a second hexagon.
  final double height;

  final ConsoleGlyphSet set;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    final ink = tint ?? colorScheme.primary;
    final glyphBox = kGlyphBox * (height / kConsoleHexHeight);

    return SizedBox(
      width: height * kHexWidthRatio,
      height: height,
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
                    width: glyphBox,
                    height: glyphBox,
                    child: CustomPaint(
                      painter: ConsoleGlyphPainter(
                        glyph: glyph,
                        color: ink,
                        set: set,
                      ),
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
