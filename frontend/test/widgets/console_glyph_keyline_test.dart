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
    for (final set in ConsoleGlyphSet.values) {
      for (final glyph in ConsoleGlyph.values) {
        test('${glyph.name} / ${set.name}', () {
          final geometry = consoleGlyphGeometry(glyph, set);
          final bounds = geometry.bounds;

          expect(
            bounds.isEmpty,
            isFalse,
            reason: '${glyph.name} draws nothing',
          );

          // Optically centred. The two declared nudges are small enough to
          // live inside the tolerance, so this holds for the whole set.
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
        });
      }
    }
  });

  test('no glyph is a hairline or a speck', () {
    // Guards the other failure direction: a mark so small it reads as dirt
    // inside a 44px terminal. Half the keyline is the floor.
    for (final set in ConsoleGlyphSet.values) {
      for (final glyph in ConsoleGlyph.values) {
        final bounds = consoleGlyphGeometry(glyph, set).bounds;
        expect(
          bounds.longestSide,
          greaterThan(kGlyphKeylineExtent),
          reason: '${glyph.name} / ${set.name} is too small to read',
        );
      }
    }
  });

  test('the schematic set covers exactly the node-relation rows', () {
    // The six fall-throughs are a design decision, not an oversight: a wiring
    // diagram for "downloaded audio cache" would be a puzzle, so those rows
    // keep the instrument drawing. If someone adds a schematic drawing for
    // one of them, that is a decision worth re-taking deliberately.
    final withSchematic = ConsoleGlyph.values
        .where(consoleGlyphHasSchematic)
        .toSet();

    expect(withSchematic, {
      ConsoleGlyph.blocked,
      ConsoleGlyph.devices,
      ConsoleGlyph.logout,
      ConsoleGlyph.deleteNode,
      ConsoleGlyph.privacy,
      ConsoleGlyph.language,
      ConsoleGlyph.push,
      ConsoleGlyph.keys,
      ConsoleGlyph.metadata,
    });

    for (final glyph in ConsoleGlyph.values.toSet().difference(withSchematic)) {
      expect(
        consoleGlyphGeometry(glyph, ConsoleGlyphSet.schematic).bounds,
        consoleGlyphGeometry(glyph, ConsoleGlyphSet.instrument).bounds,
        reason: '${glyph.name} should fall through to the instrument drawing',
      );
    }
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
    const otherSet = ConsoleGlyphPainter(
      glyph: ConsoleGlyph.privacy,
      color: Color(0xFF112233),
      set: ConsoleGlyphSet.schematic,
    );

    expect(a.shouldRepaint(same), isFalse);
    expect(a.shouldRepaint(otherSet), isTrue);
  });
}
