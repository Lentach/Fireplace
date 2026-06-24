import 'package:fireplace/utils/focus_guard_geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A composer control near the bottom of the layout viewport.
  const rect = Rect.fromLTWH(300, 700, 48, 48);

  group('focusGuardPointHitsRect', () {
    test('raw point inside the rect hits (no visual-viewport offset)', () {
      expect(
        focusGuardPointHitsRect(rect, const Offset(320, 720), Offset.zero),
        isTrue,
      );
    });

    test('point outside the rect misses with no offset', () {
      expect(
        focusGuardPointHitsRect(rect, const Offset(320, 660), Offset.zero),
        isFalse,
      );
    });

    test('iOS keyboard case: point shifted by the vv offset hits', () {
      // clientY reported in visual-viewport space (660); the visual viewport is
      // pushed 60px down, so the layout-space point (720) lands in the rect.
      expect(
        focusGuardPointHitsRect(rect, const Offset(320, 660), const Offset(0, 60)),
        isTrue,
      );
    });

    test('raw point still hits even when a vv offset exists', () {
      expect(
        focusGuardPointHitsRect(rect, const Offset(320, 720), const Offset(0, 60)),
        isTrue,
      );
    });

    test('misses when neither the raw nor the offset point is in the rect', () {
      expect(
        focusGuardPointHitsRect(rect, const Offset(320, 500), const Offset(0, 60)),
        isFalse,
      );
    });
  });

  group('focusGuardPointHitsAnyRect', () {
    final rects = [const Rect.fromLTWH(0, 0, 10, 10), rect];

    test('true when any rect matches (the second, via the offset)', () {
      expect(
        focusGuardPointHitsAnyRect(rects, const Offset(320, 660), const Offset(0, 60)),
        isTrue,
      );
    });

    test('false when no rect matches', () {
      expect(
        focusGuardPointHitsAnyRect(rects, const Offset(500, 500), Offset.zero),
        isFalse,
      );
    });

    test('empty rect set never hits', () {
      expect(
        focusGuardPointHitsAnyRect(const [], const Offset(320, 720), Offset.zero),
        isFalse,
      );
    });
  });
}
