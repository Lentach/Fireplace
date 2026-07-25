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
}
