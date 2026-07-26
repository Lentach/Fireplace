import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/widgets/console_glyphs.dart';

/// The keyline grid is the whole reason this glyph set was redrawn, so it is
/// asserted rather than eyeballed.
///
/// The set it replaced had no grid: three circles at three diameters, a
/// `signal` glyph whose mass sat entirely in the bottom half of its box, and
/// a `key` filling a third of the height next to a `shield` filling three
/// quarters. Every one of those defects is a numeric property of the
/// geometry, which means a test can hold the line instead of the next agent's
/// judgement.
void main() {
  /// A quarter of a design unit — under a third of a pixel at the 24px render
  /// size. Tight enough to catch a real drift, loose enough that a glyph
  /// whose extreme point is a rounded arc terminal is not flagged.
  const tolerance = 0.25;

  group('every glyph sits on the keyline', () {
    for (final glyph in ConsoleGlyph.values) {
      test(glyph.name, () {
        final bounds = consoleGlyphGeometry(glyph).bounds;

        expect(bounds.isEmpty, isFalse, reason: '${glyph.name} draws nothing');

        // Optically centred. The one declared nudge (the padlock) is small
        // enough to live inside the tolerance, so this holds for the set.
        expect(
          bounds.center.dx,
          closeTo(12, 0.5),
          reason: '${glyph.name} is off-centre horizontally',
        );
        expect(
          bounds.center.dy,
          closeTo(12, 0.5),
          reason: '${glyph.name} is off-centre vertically',
        );

        // Inside the canonical keyline, so no glyph out-masses its
        // neighbours on the same row rail.
        expect(
          bounds.width / 2,
          lessThanOrEqualTo(kGlyphKeylineExtent + tolerance),
          reason: '${glyph.name} is wider than the keyline',
        );
        expect(
          bounds.height / 2,
          lessThanOrEqualTo(kGlyphKeylineExtent + tolerance),
          reason: '${glyph.name} is taller than the keyline',
        );

        // The other failure direction: a mark so small it reads as dirt
        // inside a 44px terminal.
        expect(
          bounds.longestSide,
          greaterThan(kGlyphKeylineExtent),
          reason: '${glyph.name} is too small to read',
        );
      });
    }
  });

  test('appearance is a hexagon, not a disc', () {
    // Owner call, 2026-07-25: the local node is the app's only circle, so a
    // contrast DISC here would have claimed a meaning this row does not have.
    // A hexagon is wider than it is tall by exactly the pointy-top ratio; a
    // disc would be square in its bounds.
    final bounds = consoleGlyphGeometry(ConsoleGlyph.appearance).bounds;
    expect(bounds.width / bounds.height, closeTo(0.866, 0.02));
  });

  testWidgets('the painter repaints only when its inputs change', (
    tester,
  ) async {
    const a = ConsoleGlyphPainter(
      glyph: ConsoleGlyph.privacy,
      color: Color(0xFF112233),
    );
    const same = ConsoleGlyphPainter(
      glyph: ConsoleGlyph.privacy,
      color: Color(0xFF112233),
    );
    const otherGlyph = ConsoleGlyphPainter(
      glyph: ConsoleGlyph.blocked,
      color: Color(0xFF112233),
    );

    expect(a.shouldRepaint(same), isFalse);
    expect(a.shouldRepaint(otherGlyph), isTrue);
  });

  group('the selected state', () {
    /// Outline at rest, heavier and/or solid when selected — the pattern
    /// every platform ships (Material 3 "the icon becomes filled", iOS
    /// outline/filled symbol pairs, Android's two-state
    /// AnimatedVectorDrawable). Only nav glyphs have a selected state at all;
    /// a Settings row is never "selected".
    ///
    /// The bubble and the comb both fill, and both do it INSET — the fill
    /// sits inside outlines that stay visible. A flush fill on a closed
    /// silhouette is one black mass at 24px, which is the owner's verdict on
    /// the bubble's first filled attempt ("chat icone is all black"); his
    /// direction after it was "filled inside but with other lines". Only the
    /// gear cannot be filled at all, so it states selection by weight.
    const filledGlyphs = {ConsoleGlyph.chats, ConsoleGlyph.contacts};

    for (final glyph in ConsoleGlyph.values) {
      test(
        '${glyph.name} has a filled variant only if its shape takes one',
        () {
          expect(
            consoleGlyphGeometry(glyph).activeFills,
            filledGlyphs.contains(glyph) ? isNotEmpty : isEmpty,
          );
        },
      );
    }

    test('the gear states selection by weight, never by fill', () {
      expect(
        consoleGlyphGeometry(ConsoleGlyph.settings).activeFills,
        isEmpty,
        reason: 'filling the gear swallows the roots of its six spokes',
      );
      expect(kGlyphStrokeActive, greaterThan(kGlyphStroke));
    });

    test('the filled bubble keeps its message lines', () {
      // "make it same as others filled inside but with other lines" — the
      // inset alone only makes a ring, so the fill has two lines knocked out
      // of it. Their absence would leave a solid inner cell, which is the
      // thing that got rejected, so each hole is asserted by position rather
      // than inferred from a contour count.
      final fill = consoleGlyphGeometry(ConsoleGlyph.chats).activeFills.single;

      // Geometry is re-centred on resolve, so shift the design-space
      // coordinates by however far the fill actually moved.
      final delta = fill.getBounds().center - const Offset(12, 10.6);

      expect(
        fill.contains(const Offset(12, 9.2) + delta),
        isFalse,
        reason: 'the first message line must be knocked out of the fill',
      );
      expect(
        fill.contains(const Offset(11.1, 12.0) + delta),
        isFalse,
        reason: 'the second message line must be knocked out of the fill',
      );
      // And the fill is genuinely solid where it should be: between the two
      // lines, and above the first.
      expect(fill.contains(const Offset(12, 10.6) + delta), isTrue);
      expect(fill.contains(const Offset(12, 6.8) + delta), isTrue);
    });

    test('the comb keeps its seams when solid', () {
      // The three cells SHARE edges. Filling them flush merges all three into
      // one lump with no internal boundary — the silhouette survives but the
      // comb does not. Each fill must therefore stay strictly inside its own
      // cell, which a render confirmed is what keeps it legible at 24px.
      final fills = consoleGlyphGeometry(ConsoleGlyph.contacts).activeFills;
      expect(fills.length, 3);

      for (var i = 0; i < fills.length; i++) {
        for (var j = i + 1; j < fills.length; j++) {
          final overlap = Path.combine(
            PathOperation.intersect,
            fills[i],
            fills[j],
          );
          expect(
            overlap.computeMetrics().isEmpty,
            isTrue,
            reason:
                'filled cells $i and $j touch, so the comb reads as one '
                'solid lump',
          );
        }
      }

      // And a real gap, not merely a shared boundary: every fill sits clear
      // of its neighbours by more than the stroke that separates them.
      final centres = [for (final f in fills) f.getBounds().center];
      final gap =
          (centres[1] - centres[2]).distance -
          fills[1].getBounds().width / 2 -
          fills[2].getBounds().width / 2;
      expect(
        gap,
        greaterThan(kGlyphStroke),
        reason: 'the gap between adjacent fills must clear the shared stroke',
      );
    });
  });
}
