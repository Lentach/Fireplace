import 'package:flutter/widgets.dart' show Offset, Rect;

/// Pure hit-test for the iOS-WebKit composer focus guard.
///
/// Guard rects are registered in Flutter's `localToGlobal` space (layout-viewport
/// logical px). A pointer event's `clientX`/`clientY`, however, may be reported
/// relative to the **visual** viewport, which iOS offsets while the soft keyboard
/// is up (`visualViewport.offsetLeft`/`offsetTop` > 0). The browser's exact
/// convention here is version-dependent and cannot be assumed, so we accept a hit
/// in EITHER space: the raw [point], or the point shifted into layout space by
/// [vvOffset]. When there is no visual-viewport offset the two are identical, so
/// this is a strict superset of a plain `rect.contains(point)` — it can only make
/// the guard fire when it previously (wrongly) did not.
bool focusGuardPointHitsRect(Rect rect, Offset point, Offset vvOffset) {
  if (rect.contains(point)) return true;
  if (vvOffset != Offset.zero && rect.contains(point + vvOffset)) return true;
  return false;
}

/// True if [point] hits any of [rects] in either coordinate space — see
/// [focusGuardPointHitsRect].
bool focusGuardPointHitsAnyRect(
  Iterable<Rect> rects,
  Offset point,
  Offset vvOffset,
) {
  for (final rect in rects) {
    if (focusGuardPointHitsRect(rect, point, vvOffset)) return true;
  }
  return false;
}
