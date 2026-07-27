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
import 'icon_selection.dart';

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

/// Stroke weight when a glyph is SELECTED.
///
/// Weight is what states selection on a mark that cannot take a fill. The
/// device verdict that established this was the bubble: a single closed
/// silhouette filled flush is just a black hexagon at 24px, and on a light
/// theme, where the accent is nearly black, that is all you see ("chat icone
/// is all black").
///
/// The gear is on weight for the same structural reason, though that one is
/// a judgement call from a render rather than an owner verdict: its teeth are
/// thin spokes rooted inside the body, so a flush fill swallows their roots
/// and leaves a 6-point star with a pinhole. Only the comb, whose fill is
/// INSET inside cells that keep their outlines, still carries
/// [ConsoleGlyphGeometry.activeFills].
const double kGlyphStrokeActive = 2.5;

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

  /// Bottom-nav: a conversation is a LINK — two nodes joined by a live trace,
  /// on the honeycomb's own 60° neighbour angle.
  chats,

  /// Bottom-nav: the board itself — a three-cell honeycomb cluster.
  contacts,

  /// Bottom-nav: Settings. A gear wearing the cell — teeth on the hex's six
  /// POINTS, bore through the middle (owner pick G3, 2026-07-26).
  settings,
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
    this.activeFills = const [],
  });

  /// Drawn with [kGlyphStroke], round caps and joins.
  final List<Path> strokes;

  /// Drawn solid. Used sparingly — only where a filled region IS the mark.
  final List<Path> fills;

  /// Filled terminals of radius [kGlyphDotRadius].
  final List<Offset> dots;

  /// Solid regions painted only when the glyph is SELECTED, flooded in.
  ///
  /// Deliberately INSET rather than flush with the outline. Filling a glyph
  /// out to its own silhouette turns it into one black mass at 24px — the
  /// owner rejected exactly that on the bubble ("chat icone is all black").
  /// What survives is a fill that leaves the outline and its interior
  /// negative space visible, so the mark still reads as itself.
  ///
  /// Contained within the stroked mark by construction — the comb's cells are
  /// deliberately INSET, not congruent — so this never moves [bounds], which
  /// is measured from [strokes], [fills] and [dots] only.
  final List<Path> activeFills;

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
    activeFills: [for (final p in activeFills) p.shift(d)],
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

/// A point at [angleDegrees] and [radius] from the design-space centre.
/// Polar placement keeps radial sets (gear teeth, spokes) exactly regular
/// instead of hand-rounded per point.
Offset _radial(double angleDegrees, double radius) {
  final radians = angleDegrees * math.pi / 180;
  return Offset(
    _c.dx + radius * math.cos(radians),
    _c.dy + radius * math.sin(radians),
  );
}

/// The pointy-top hex's six POINTS. Its six flats sit 30° off these.
const List<double> _hexVertexAngles = [30, 90, 150, 210, 270, 330];

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
      // The meridian globe, wearing the cell (owner, this session: "language
      // icone is not hex too … maybe just make a hex instead of round globe").
      //
      // Still a CONVENTIONAL silhouette, the same licence `metadata` takes,
      // and for the same reason: "language" has no truthful node relation to
      // draw. Three attempts at one proved it — a node with two encodings
      // stacked to its right (what shipped first) reads as a bullet list, two
      // cells carrying different scripts mush into a bowtie at 24px, and the
      // same idea diverging on hex angles reads as scissors. A globe survives
      // the size, which is the only test that matters on a 44px terminal.
      //
      // The shell is now the hex, so the row stops being the one round mark
      // in a hex set. Meridian and equator are pulled deliberately OFF that
      // shell — 1.6 of clearance at the poles, 0.93 at the flats. The version
      // that simply swapped circle for hex kept the old 7.6/15.2 oval and
      // crowded to within 0.8 and 0.33; three 1.8 strokes inside a 16-unit
      // hex is what makes this mark choke at 24px, and clearance is the cure.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(_c, 8.0),
          _oval(_c, 7.0, 12.8),
          _line(const Offset(6.0, 12), const Offset(18.0, 12)),
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
      // A padlock whose body IS a cell (owner, this session: the padlock
      // "doesnt really fit the rest hex theme"). Deliberately a different
      // OBJECT from [keys], which is identity material, so the two rows can
      // never be read as the same thing.
      //
      // Drawn as a TRUE U: two legs rooted in the body's upper edges with a
      // half hoop above them. A pointy-top hex fights a shackle — its top
      // point rises into the opening — so the two constructions that hung an
      // arc straight off the body both read as a handbag, one as an avocado.
      // Lifting the hoop clear of the point and dropping legs to meet the
      // shoulders is what makes this read as a lock at 24px.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(const Offset(12, 15.9), 5.2),
          _line(const Offset(9.4, 9.2), const Offset(9.4, 12.2)),
          _line(const Offset(14.6, 9.2), const Offset(14.6, 12.2)),
          _arc(const Offset(12, 9.2), 2.6, math.pi, math.pi),
        ],
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

    case ConsoleGlyph.chats:
      // A hex speech bubble — the app's own cell doing the bubble job.
      //
      // Owner pick, 2026-07-26. The first drawing was two small nodes joined
      // by a trace, which at 24px was `blocked` minus its slash: two dots and
      // a hairline. Nav glyphs are the most-glanced marks in the app and must
      // differ in GROSS SILHOUETTE, not in detail — so this one is a single
      // closed shape with a spur, against the lattice and the radial core it
      // sits beside.
      //
      // Its SELECTED state is an INSET fill, matching the comb (owner: "chats
      // icon can be filled in but no all one color inside icone make it same
      // as others filled inside but with other lines"). Filling it out to its
      // own silhouette was the earlier attempt and it is one black hexagon at
      // 24px — worse on a light theme, where the accent is nearly black:
      // "chat icone is all black". Insetting keeps the outline and the tail
      // reading as lines with the solid sitting inside them.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(const Offset(12, 10.6), 6.8),
          _poly(const [
            Offset(9.2, 16.2),
            Offset(6.3, 19.8),
            Offset(11.4, 17.3),
          ]),
        ],
        activeFills: [
          // Inner cell, with two message lines knocked back out of it. The
          // inset alone would only give a ring; the lines are what keep the
          // filled state reading as a CHAT bubble instead of a solid cell,
          // and they sit inside the hex's full-width band (y 8.0–13.2) so
          // neither one clips a sloping edge.
          Path.combine(
            PathOperation.difference,
            _hexNode(const Offset(12, 10.6), 5.2),
            Path()
              ..addRRect(
                RRect.fromRectAndRadius(
                  const Rect.fromLTRB(8.4, 8.45, 15.6, 9.95),
                  const Radius.circular(0.75),
                ),
              )
              ..addRRect(
                RRect.fromRectAndRadius(
                  const Rect.fromLTRB(8.4, 11.25, 13.8, 12.75),
                  const Radius.circular(0.75),
                ),
              ),
          ),
        ],
      );

    case ConsoleGlyph.contacts:
      // Three cells sharing edges on the true honeycomb pitch — the board in
      // miniature.
      //
      // Owner pick (C1), 2026-07-26. Chosen over a 4-cell diamond and a
      // 7-cell flower: fewer and bigger survives 24px on a phone, and the
      // shared edges read as one comb rather than as separate marks.
      //
      // The three cells are separate active fills on purpose: they flood in
      // sequence, which is the per-icon character an authored Lottie file
      // would otherwise have to supply by hand.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(const Offset(12, 8.3), 4.6),
          _hexNode(const Offset(8.0163, 15.2), 4.6),
          _hexNode(const Offset(15.9837, 15.2), 4.6),
        ],
        activeFills: [
          // Inset by the stroke half-width plus a hairline of clearance.
          // Filling these cells to their outline would merge all three into
          // one solid lump — they SHARE edges, so the seams that make it read
          // as a comb are exactly what a flush fill destroys.
          _hexNode(const Offset(12, 8.3), 3.2),
          _hexNode(const Offset(8.0163, 15.2), 3.2),
          _hexNode(const Offset(15.9837, 15.2), 3.2),
        ],
      );

    case ConsoleGlyph.settings:
      // The gear, dressed in the cell.
      //
      // Owner direction, 2026-07-26: "modify a bit current icon for setting
      // which is a gear - just dress it up in a cube". Teeth sit on the six
      // POINTS rather than the flats (his pick of four drawings) and the bore
      // stays open at 24px, which is what keeps it a gear rather than a sun.
      //
      // This REPLACED a circle-with-cardinal-ticks reading of "your local
      // node". That one measured fine and still failed: at true size four
      // ticks on a ring is a gunsight.
      //
      // Its SELECTED state is weight, not fill — a judgement call from a
      // render, not an owner verdict. Filling this body swallows the roots of
      // six spokes and leaves a 6-point star with a pinhole; the bore and the
      // teeth are the whole identity here, so the gear keeps every line and
      // simply gets heavier.
      return ConsoleGlyphGeometry(
        strokes: [
          _hexNode(_c, 5.6),
          for (final angle in _hexVertexAngles)
            _line(_radial(angle, 5.0), _radial(angle, 8.0)),
          _circle(_c, 2.0),
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
/// implies and the mark sits low without the lift. Still true now that the
/// body is a hex cell — the U-shackle above it is thinner line-work over a
/// wider closed form, which is the same imbalance.
Offset _opticalNudge(ConsoleGlyph glyph) =>
    glyph == ConsoleGlyph.password ? const Offset(0, -0.35) : Offset.zero;

/// Sub-region [index]'s own 0..1 progress within the whole transition.
///
/// Regions flood in sequence with a long overlap, which is what makes the
/// comb's three cells light one after another — the per-icon character that
/// an authored Lottie file would otherwise have to supply by hand.
double _regionProgress(double t, int index, int count) {
  if (count <= 1) return t;
  const span = 0.66;
  final start = index * (1 - span) / (count - 1);
  return ((t - start) / span).clamp(0.0, 1.0);
}

/// Stroke weight this glyph reaches when fully selected.
///
/// Only the GEAR states selection by weight, and only because it is the one
/// mark here that cannot be filled at all: its teeth are thin spokes rooted
/// inside the body, so any fill swallows their roots. The bubble and the comb
/// both carry inset fills instead, and their strokes deliberately do NOT
/// thicken — a heavier outline would close the narrow gap that keeps each
/// fill visibly separate from the line around it, which is the whole reason
/// the fills are inset.
double _activeStroke(ConsoleGlyph glyph) =>
    glyph == ConsoleGlyph.settings ? kGlyphStrokeActive : kGlyphStroke;

/// Per-glyph motion on selection.
///
/// Each nav glyph moves in a way only that mark could: the gear turns, the
/// bubble lifts, the comb's cells come apart and reassemble. This is the
/// thing that makes an authored icon set feel alive — Telegram ships a
/// separate Lottie file per tab icon for exactly this reason — and it costs
/// nothing here because the glyphs are already path data.
///
/// All three are TRANSIENT: every one returns to zero at t = 1, so the
/// resting and selected drawings are identical and only the travel is seen.

/// How far the gear turns. One tooth pitch, because the mark is 6-fold
/// symmetric so 60° maps it onto itself and the travel reads as engaging a
/// notch. (The owner suggested 45°; since the rotation settles back to zero
/// either way, that was a taste call on my part, not a constraint.)
double _selectedSpin(ConsoleGlyph glyph) =>
    glyph == ConsoleGlyph.settings ? -math.pi / 3 : 0;

/// How far the comb's cells fly apart at the peak, in design units.
const double _kCellSpread = 2.2;

/// How far the bubble lifts at the peak, in design units.
const double _kBubbleLift = 1.6;

/// A 0 → 1 → 0 bump. Eased on the way out so the return settles rather than
/// snapping, and exactly zero at both ends so nothing is left displaced.
double _bump(double t) {
  if (t <= 0 || t >= 1) return 0;
  return math.sin(t * math.pi);
}

/// Displacement for one sub-path of [glyph] at time [t].
///
/// For the comb this is radial: each cell is pushed straight out from the
/// glyph centre and pulled back, so the board visibly comes apart and
/// reassembles. For the bubble the whole mark lifts. Geometry is centred on
/// resolve, so the glyph centre is [_c] by construction and the direction can
/// be read straight off the sub-path's own bounds.
Offset _motionOffset(ConsoleGlyph glyph, Path subPath, double t) {
  final bump = _bump(t);
  if (bump == 0) return Offset.zero;
  switch (glyph) {
    case ConsoleGlyph.contacts:
      final d = subPath.getBounds().center - _c;
      if (d.distance == 0) return Offset.zero;
      return d / d.distance * (_kCellSpread * bump);
    case ConsoleGlyph.chats:
      return Offset(0, -_kBubbleLift * bump);
    default:
      return Offset.zero;
  }
}

class ConsoleGlyphPainter extends CustomPainter {
  const ConsoleGlyphPainter({
    required this.glyph,
    required this.color,
    this.progress = 0,
    this.activeColor,
  });

  final ConsoleGlyph glyph;

  /// The outline color. Static call sites pass their tint and get exactly the
  /// mark they always got.
  final Color color;

  /// How far into the SELECTED state this mark is: 0 = resting, 1 = fully
  /// selected. What that looks like is per glyph — heavier stroke for the
  /// bubble and the gear, inset cells flooding for the comb — because a flush
  /// fill on a closed silhouette is a black lump at 24px. Defaults to 0, so
  /// every static call site is unaffected.
  final double progress;

  /// Color of the flooded fill, for the glyphs that have one. Falls back to
  /// [color].
  final Color? activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = consoleGlyphGeometry(glyph);
    final t = progress.clamp(0.0, 1.0);

    canvas.save();
    canvas.scale(size.width / kGlyphUnit, size.height / kGlyphUnit);

    // Turn into place. Transient: it starts a notch back and unwinds to the
    // resting orientation, so the resting and selected drawings are identical
    // and only the travel is visible.
    final spin = _selectedSpin(glyph);
    if (spin != 0 && t > 0 && t < 1) {
      canvas.translate(_c.dx, _c.dy);
      canvas.rotate(spin * (1 - t));
      canvas.translate(-_c.dx, -_c.dy);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kGlyphStroke + (_activeStroke(glyph) - kGlyphStroke) * t
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;

    // The outline is ALWAYS whole. That is what makes this a state change
    // rather than an entrance: the mark never leaves, it gains mass.
    for (final path in geometry.fills) {
      canvas.drawPath(path, fill);
    }
    for (final path in geometry.strokes) {
      canvas.drawPath(path.shift(_motionOffset(glyph, path, t)), stroke);
    }
    for (final dot in geometry.dots) {
      canvas.drawCircle(dot, kGlyphDotRadius, fill);
    }

    if (t > 0 && geometry.activeFills.isNotEmpty) {
      final active = Paint()..color = activeColor ?? color;
      for (var i = 0; i < geometry.activeFills.length; i++) {
        // Each fill rides with the cell it belongs to. For the comb the two
        // lists are index-aligned one-per-cell, which the keyline test pins.
        final shift = _motionOffset(glyph, geometry.activeFills[i], t);
        final region = geometry.activeFills[i].shift(shift);
        final local = _regionProgress(t, i, geometry.activeFills.length);
        if (local <= 0) continue;
        canvas.save();
        if (local < 1) {
          // Flood from the region's own centre so the solid grows into the
          // outline instead of cross-fading with it.
          final b = region.getBounds();
          canvas.clipPath(
            Path()..addOval(
              Rect.fromCircle(
                center: b.center,
                radius: b.longestSide * 0.75 * local,
              ),
            ),
          );
        }
        canvas.drawPath(region, active);
        canvas.restore();
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ConsoleGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor;
}

/// A console glyph as a drop-in icon: reads its color and size from the
/// ambient [IconTheme], exactly like [Icon] does, so any container that
/// tints its icons (e.g. the bottom nav's selection tween) drives the glyph
/// without knowing this system exists.
///
/// It also honours [IconSelection], so chrome with a selected state gets the
/// change for free — heavier stroke, or flooded inset regions, depending on
/// what the glyph's shape can carry. With no [IconSelection] ancestor the
/// progress is 0 and this is the plain resting mark.
class ConsoleGlyphIcon extends StatelessWidget {
  const ConsoleGlyphIcon(this.glyph, {super.key});

  final ConsoleGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = iconTheme.size ?? kGlyphBox;
    final selection = IconSelection.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: ConsoleGlyphPainter(
        glyph: glyph,
        color: iconTheme.color ?? const Color(0xFF000000),
        progress: selection?.progress ?? 0,
        activeColor: selection?.activeColor,
      ),
    );
  }
}
