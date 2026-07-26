/// The Settings console glyph set.
///
/// The first hand-drawn set (2026-07-25) failed for a reason worth recording:
/// eight of its nine glyphs were Material icons redrawn by hand — a shield
/// with a check is `Icons.verified_user`, a laptop is `Icons.laptop`, a
/// slashed circle is `Icons.block`. Drawing clip art by hand does not stop it
/// being clip art; it only loses Material's optical tuning. And there was no
/// grid behind it: three circles at three diameters (8, 7.8, 7.6), a `signal`
/// glyph whose mass sat entirely in the bottom half of its box, and a `key`
/// that filled a third of the height while `shield` filled three quarters.
///
/// This file fixes both halves of that failure.
///
/// **Craft.** Every glyph is built on ONE keyline grid in a 24-unit design
/// space that is also the render size, so no coordinate lands on a fraction
/// of a pixel. There is one canonical circle, one canonical square, one
/// canonical hexagon, one stroke weight, one terminal radius. Geometry is
/// produced as data ([ConsoleGlyphGeometry]) rather than painted inline, and
/// every glyph is re-centred on its own tight bounds before it is drawn —
/// optical centring is a property of the system here, not of one author's
/// arithmetic. `console_glyph_keyline_test.dart` measures it.
///
/// **Concept — settled by the owner on 2026-07-25 from a rendered A/B.** The
/// set is a WIRING DIAGRAM of what each row does to your node, drawn from the
/// app's own primitives: the hex cell, the trace, the terminal. That follows
/// the owner's rationale for the whole language — the app reads as the inside
/// of a computer, and every Settings row is a facet of your own node.
///
/// It is not applied dogmatically. Six rows have no truthful node reading
/// ("downloaded audio cache" is not a node relation), and `metadata` is an
/// owner call: the server stack says "the machine that holds this" better
/// than a node wired to a box. Those keep a conventional silhouette, built to
/// the same grid so the set still reads as one hand.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hex_avatar.dart';

/// Design space. Deliberately equal to the rendered box (see [kGlyphBox]) so
/// the scale factor is exactly 1 and every coordinate is pixel-predictable.
const double kGlyphUnit = 24;

/// Rendered size of a glyph inside the 44px hex terminal. 24/44 sits in the
/// standard icon-in-container band and is what lets the mark actually read;
/// the previous 22 was quietly small for the frame around it.
const double kGlyphBox = 24;

/// One weight for the whole set. Heavier than the 1.4 hex terminal outline so
/// the glyph is the subject and the terminal is the frame.
const double kGlyphStroke = 1.8;

/// Keyline: the canonical circle (Ø15), square (15×15) and pointy-top hexagon
/// (14.2 × 16.4). No glyph may exceed this distance from centre on either
/// axis; the keyline test enforces it.
const double kGlyphKeylineExtent = 8.2;

/// Radius of a filled terminal.
const double kGlyphDotRadius = 1.5;

const Offset _c = Offset(12, 12);
const double _squareHalf = 7.5;
const double _hexR = 8.2;

/// Semantic names, not shape names. The old set was named after its drawings
/// (`palette`, `globe`, `nodeX`), which is why re-drawing it meant renaming
/// every call site. These names survive a redraw.
enum ConsoleGlyph {
  /// Theme + chat background. On the Settings root this is replaced by a live
  /// `AppearancePreview`; the glyph is what the Appearance sub-screen uses.
  appearance,
  language,
  privacy,
  blocked,
  devices,
  push,
  password,
  deleteNode,
  logout,

  /// Signal identity key material — distinct from [password], which is a
  /// credential you type.
  keys,
  webStorage,
  media,
  metadata,
  quantum,
  cache,
}

/// A glyph as data: stroked outlines, filled regions, and filled terminals.
///
/// Kept separate from painting so the keyline contract is measurable. A test
/// can assert centring and extent instead of an agent asserting them in a
/// comment.
@immutable
class ConsoleGlyphGeometry {
  const ConsoleGlyphGeometry({
    this.strokes = const [],
    this.fills = const [],
    this.dots = const [],
  });

  /// Drawn with [kGlyphStroke], round caps and joins.
  final List<Path> strokes;

  /// Drawn solid. Used sparingly — only where a filled region IS the mark.
  final List<Path> fills;

  /// Filled terminals of radius [kGlyphDotRadius].
  final List<Offset> dots;

  /// Union of everything, ignoring stroke width (which is uniform across the
  /// set and so cannot shift the centre).
  ///
  /// Measured by walking the contours rather than calling `Path.getBounds`,
  /// which is deliberately CONSERVATIVE: for an arc or a rotated oval it
  /// bounds the Bézier control points, not the curve. That over-reports by
  /// up to ~20% here, and since [centred] divides by this rectangle it was
  /// visibly mis-centring every arc-based glyph. The keyline test catches it.
  Rect get bounds {
    double? minX, minY, maxX, maxY;
    void addPoint(double x, double y) {
      minX = minX == null ? x : math.min(minX!, x);
      minY = minY == null ? y : math.min(minY!, y);
      maxX = maxX == null ? x : math.max(maxX!, x);
      maxY = maxY == null ? y : math.max(maxY!, y);
    }

    // 48 samples per contour resolves these shapes well past the 0.25-unit
    // tolerance the test holds them to.
    const samples = 48;
    for (final path in [...strokes, ...fills]) {
      for (final metric in path.computeMetrics()) {
        if (metric.length == 0) continue;
        for (var i = 0; i <= samples; i++) {
          final t = metric.getTangentForOffset(metric.length * i / samples);
          if (t != null) addPoint(t.position.dx, t.position.dy);
        }
      }
    }
    for (final d in dots) {
      addPoint(d.dx - kGlyphDotRadius, d.dy - kGlyphDotRadius);
      addPoint(d.dx + kGlyphDotRadius, d.dy + kGlyphDotRadius);
    }
    if (minX == null) return Rect.zero;
    return Rect.fromLTRB(minX!, minY!, maxX!, maxY!);
  }

  ConsoleGlyphGeometry shift(Offset d) => ConsoleGlyphGeometry(
    strokes: [for (final p in strokes) p.shift(d)],
    fills: [for (final p in fills) p.shift(d)],
    dots: [for (final o in dots) o + d],
  );

  /// Translates so the bounding box centres on the design-space centre, plus
  /// an optional optical [nudge] for shapes whose visual weight is not their
  /// geometric middle.
  ConsoleGlyphGeometry centred({Offset nudge = Offset.zero}) {
    final b = bounds;
    if (b.isEmpty) return this;
    return shift(_c - b.center + nudge);
  }
}

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

Path _poly(List<Offset> pts, {bool close = false}) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final o in pts.skip(1)) {
    p.lineTo(o.dx, o.dy);
  }
  if (close) p.close();
  return p;
}

Path _line(Offset a, Offset b) => _poly([a, b]);

Path _oval(Offset c, double w, double h) =>
    Path()..addOval(Rect.fromCenter(center: c, width: w, height: h));

Path _circle(Offset c, double r) =>
    Path()..addOval(Rect.fromCircle(center: c, radius: r));

Path _rrect(Rect r, double radius) =>
    Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));

Path _arc(Offset c, double r, double start, double sweep) =>
    Path()..addArc(Rect.fromCircle(center: c, radius: r), start, sweep);

Path _rotated(Path p, double radians) => p.transform(
  (Matrix4.identity()
        ..translateByDouble(_c.dx, _c.dy, 0, 1)
        ..rotateZ(radians)
        ..translateByDouble(-_c.dx, -_c.dy, 0, 1))
      .storage,
);

/// A hex cell — the same pointy-top hexagon the honeycomb draws, so the
/// glyphs and the board are literally one shape.
Path _hexNode(Offset c, double r) => hexPath(c, r);

/// Straight trace. Horizontal, vertical or on a hex angle; never arbitrary.
Path _trace(Offset a, Offset b) => _line(a, b);

/// The 45° arrowhead, shared so no two arrows disagree.
Path _arrowHead(Offset tip, {double size = 3.0}) => _poly([
  Offset(tip.dx - size, tip.dy - size),
  tip,
  Offset(tip.dx - size, tip.dy + size),
]);

// ---------------------------------------------------------------------------
// The set
// ---------------------------------------------------------------------------

ConsoleGlyphGeometry _draw(ConsoleGlyph glyph) {
  switch (glyph) {
    case ConsoleGlyph.appearance:
      // Contrast mark on the HEX, not a disc (owner call): the local node is
      // the app's only circle, so a circle here would have claimed a meaning
      // this row does not have. Half the cell is solid, which is the standard
      // "appearance" mark and the one deliberate fill in the set.
      final cell = _hexNode(_c, _hexR);
      return ConsoleGlyphGeometry(
        strokes: [cell],
        fills: [
          Path.combine(
            PathOperation.intersect,
            cell,
            Path()..addRect(const Rect.fromLTRB(0, 0, 12, 24)),
          ),
        ],
      );

    case ConsoleGlyph.language:
      // One node, two traces carrying the same link in two encodings.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(const Offset(7.6, 12), 4.3),
          _trace(const Offset(11.4, 9.2), const Offset(20.2, 9.2)),
          _trace(const Offset(11.4, 14.8), const Offset(13.8, 14.8)),
          _trace(const Offset(15.2, 14.8), const Offset(17.6, 14.8)),
          _trace(const Offset(19.0, 14.8), const Offset(20.2, 14.8)),
        ],
      );

    case ConsoleGlyph.privacy:
      // Your node inside a shell that is open top and bottom — protection,
      // not a sealed box.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(_c, 4.8),
          _arc(_c, 8.0, 2 * math.pi / 3, 2 * math.pi / 3),
          _arc(_c, 8.0, -math.pi / 3, 2 * math.pi / 3),
        ],
      );

    case ConsoleGlyph.blocked:
      // Two nodes, the link between them, and a slash killing it.
      //
      // The first drawing was a purely schematic "open circuit": a 1.8-unit
      // gap with two cap strokes. At the size this actually ships (24px) the
      // gap is under two pixels, so it read as two nodes JOINED — the exact
      // opposite of the word on the row. A legibility failure is not fixed
      // with a second subtle idea, so the negation is the universal slash,
      // carried over the node pair rather than over a bare circle.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(const Offset(6.6, 12), 3.2),
          _hexNode(const Offset(17.4, 12), 3.2),
          _trace(const Offset(9.37, 12), const Offset(14.63, 12)),
          _line(const Offset(7.2, 18.4), const Offset(16.8, 5.6)),
        ],
      );

    case ConsoleGlyph.devices:
      // A chip: the node with its pin-out.
      //
      // The first drawing was the node plus one downward terminal, which at
      // true size read as a balloon on a string. Pins on both flanks say
      // "hardware" instantly, and they are the most literal possible take on
      // the rationale for this whole language.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(_c, 6.0),
          for (final y in const [9.0, 12.0, 15.0]) ...[
            _line(Offset(4.2, y), Offset(6.9, y)),
            _line(Offset(17.1, y), Offset(19.8, y)),
          ],
        ],
      );

    case ConsoleGlyph.push:
      // The node broadcasting.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(const Offset(12, 15.4), 4.4),
          _arc(const Offset(12, 11.0), 4.2, -0.81 * math.pi, 0.62 * math.pi),
          _arc(const Offset(12, 11.0), 7.2, -0.81 * math.pi, 0.62 * math.pi),
        ],
      );

    case ConsoleGlyph.password:
      // A padlock: a credential you type. Deliberately a different OBJECT
      // from [keys], which is identity material, so the two rows can never be
      // read as the same thing.
      return ConsoleGlyphGeometry(
        strokes: [
          _rrect(const Rect.fromLTRB(5.4, 11.2, 18.6, 19.8), 1.8),
          _arc(const Offset(12, 11.2), 4.2, math.pi, math.pi),
        ],
        dots: const [Offset(12, 15.5)],
      );

    case ConsoleGlyph.deleteNode:
      // Your node, struck out. The row already carries the red edge, title
      // and terminal tint; the mark only has to be unmistakable.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(_c, _hexR),
          _line(const Offset(8.4, 8.4), const Offset(15.6, 15.6)),
          _line(const Offset(15.6, 8.4), const Offset(8.4, 15.6)),
        ],
      );

    case ConsoleGlyph.logout:
      // The node detaching along its trace.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(const Offset(8.6, 12), 5.6),
          _trace(const Offset(13.45, 12), const Offset(20.2, 12)),
          _arrowHead(const Offset(20.2, 12), size: 2.8),
        ],
      );

    case ConsoleGlyph.keys:
      // The node itself is keyed — the identity material IS the node.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(_c, 7.0),
          _circle(const Offset(12, 10.6), 2.0),
          _line(const Offset(12, 12.6), const Offset(12, 15.6)),
        ],
      );

    case ConsoleGlyph.webStorage:
      return ConsoleGlyphGeometry(
        strokes: [
          _rrect(const Rect.fromLTRB(3.8, 5.4, 20.2, 18.6), 2.0),
          _line(const Offset(3.8, 9.4), const Offset(20.2, 9.4)),
        ],
        dots: const [Offset(6.6, 7.4), Offset(9.4, 7.4)],
      );

    case ConsoleGlyph.media:
      // Every ridge is 45°, so the plate agrees with the arrowheads instead
      // of introducing another angle family.
      return ConsoleGlyphGeometry(
        strokes: [
          _rrect(
            Rect.fromCenter(
              center: _c,
              width: _squareHalf * 2,
              height: _squareHalf * 2,
            ),
            2.2,
          ),
          _circle(const Offset(9.2, 9.4), 1.8),
          _poly(const [
            Offset(5.4, 17.4),
            Offset(10.4, 12.4),
            Offset(13.4, 15.4),
            Offset(15.6, 13.2),
            Offset(18.6, 16.2),
          ]),
        ],
      );

    case ConsoleGlyph.metadata:
      // A server stack — OWNER CALL over the node-wired-to-a-box diagram.
      // The row is about the machine that holds the metadata, and the stack
      // says that directly.
      return ConsoleGlyphGeometry(
        strokes: [
          _rrect(const Rect.fromLTRB(4.5, 4.6, 19.5, 8.2), 1.6),
          _rrect(const Rect.fromLTRB(4.5, 10.2, 19.5, 13.8), 1.6),
          _rrect(const Rect.fromLTRB(4.5, 15.8, 19.5, 19.4), 1.6),
        ],
        fills: [
          _circle(const Offset(7.4, 6.4), 0.85),
          _circle(const Offset(7.4, 12.0), 0.85),
          _circle(const Offset(7.4, 17.6), 0.85),
        ],
      );

    case ConsoleGlyph.quantum:
      // Three orbits, not two: two alone leave the mark visibly narrower than
      // every neighbour on the same rail.
      return ConsoleGlyphGeometry(
        strokes: [
          _oval(_c, 16.4, 7.0),
          _rotated(_oval(_c, 16.4, 7.0), math.pi / 3),
          _rotated(_oval(_c, 16.4, 7.0), -math.pi / 3),
        ],
        dots: const [_c],
      );

    case ConsoleGlyph.cache:
      return ConsoleGlyphGeometry(
        strokes: [
          _line(const Offset(12, 4.6), const Offset(12, 13.6)),
          _poly(const [
            Offset(8.4, 10.2),
            Offset(12, 13.8),
            Offset(15.6, 10.2),
          ]),
          _poly(const [
            Offset(4.6, 15.4),
            Offset(4.6, 19.4),
            Offset(19.4, 19.4),
            Offset(19.4, 15.4),
          ]),
        ],
      );
  }
}

/// Resolved, centred geometry for one glyph. Pure — the keyline test calls
/// this directly rather than reading pixels.
ConsoleGlyphGeometry consoleGlyphGeometry(ConsoleGlyph glyph) =>
    _resolved[glyph] ??= _draw(glyph).centred(nudge: _opticalNudge(glyph));

/// Resolving walks every contour to measure tight bounds, and a console can
/// hold a dozen terminals, so the result is cached. The geometry is pure and
/// immutable, so one entry per glyph is correct forever.
final Map<ConsoleGlyph, ConsoleGlyphGeometry> _resolved = {};

/// Bounding-box centring is right for almost everything. This is the shape
/// whose visual weight is not its geometric middle: the padlock's shackle is
/// open line-work above a closed body, so the body reads heavier than the box
/// implies and the mark sits low without the lift.
Offset _opticalNudge(ConsoleGlyph glyph) =>
    glyph == ConsoleGlyph.password ? const Offset(0, -0.35) : Offset.zero;

class ConsoleGlyphPainter extends CustomPainter {
  const ConsoleGlyphPainter({required this.glyph, required this.color});

  final ConsoleGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = consoleGlyphGeometry(glyph);

    canvas.save();
    canvas.scale(size.width / kGlyphUnit, size.height / kGlyphUnit);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kGlyphStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;

    for (final path in geometry.fills) {
      canvas.drawPath(path, fill);
    }
    for (final path in geometry.strokes) {
      canvas.drawPath(path, stroke);
    }
    for (final dot in geometry.dots) {
      canvas.drawCircle(dot, kGlyphDotRadius, fill);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ConsoleGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
