import 'dart:math' as math;

/// Pure arithmetic behind the iOS WebKit visualViewport keyboard-inset source
/// (`web_keyboard_inset_web.dart`). Extracted so the running-max / occlusion /
/// noise-floor logic is unit-testable on the VM — the DOM listener plumbing is
/// not.
///
/// Insets smaller than [kMinKeyboardInset] are treated as 0 — rounding /
/// safe-area noise. A real soft keyboard is always far taller (~250px+).
const double kMinKeyboardInset = 80.0;

/// Result of one keyboard-inset recomputation step.
class KeyboardInsetComputation {
  const KeyboardInsetComputation({
    required this.fullLayoutHeight,
    required this.trackedWidth,
    required this.inset,
  });

  /// New running-max full (pre-keyboard) layout height.
  final double fullLayoutHeight;

  /// Width the running max is valid for (reset key for orientation changes).
  final double trackedWidth;

  /// Keyboard occlusion in Flutter's (unshrunk) scene; 0 below the noise floor.
  final double inset;
}

/// One recomputation step for the visualViewport keyboard inset.
///
/// The full (pre-keyboard) layout height is tracked as a running max. iOS keeps
/// the *layout* viewport at the full height when the keyboard opens, but in a
/// standalone PWA `window.innerHeight` SHRINKS to the above-keyboard height, so
/// it can't be used live as the layout reference. The max is fed from every
/// signal that reflects the full height:
///  - `innerHeight` (full while the keyboard is down),
///  - `documentElement.clientHeight` (the layout viewport; stays full),
///  - `vvHeight + vvOffsetTop` (the visual viewport's bottom edge in layout
///    space; equals the layout height when the page is panned to the bottom).
/// A running max is safe: the keyboard only shrinks these, never grows the true
/// layout height. A width change (orientation) resets the captured height.
///
/// Keyboard occlusion = full layout height minus the above-keyboard visible
/// height. NOT minus `vvOffsetTop`: the offset is the OS pan (countered by the
/// viewport pin), not part of the keyboard height.
KeyboardInsetComputation computeKeyboardInset({
  required double previousFullLayoutHeight,
  required double previousTrackedWidth,
  required double vvHeight,
  required double vvWidth,
  required double vvOffsetTop,
  required double innerHeight,
  required double clientHeight,
}) {
  var fullLayoutHeight = previousFullLayoutHeight;
  var trackedWidth = previousTrackedWidth;

  // Orientation change: drop the captured height and re-capture below.
  if ((vvWidth - trackedWidth).abs() > 1) {
    trackedWidth = vvWidth;
    fullLayoutHeight = 0;
  }

  fullLayoutHeight = math.max(
    fullLayoutHeight,
    math.max(innerHeight, math.max(clientHeight, vvHeight + vvOffsetTop)),
  );

  final occluded = fullLayoutHeight - vvHeight;
  return KeyboardInsetComputation(
    fullLayoutHeight: fullLayoutHeight,
    trackedWidth: trackedWidth,
    inset: occluded > kMinKeyboardInset ? occluded : 0,
  );
}
