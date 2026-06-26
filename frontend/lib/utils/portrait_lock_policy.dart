import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';

bool shouldShowRotateOverlay({
  required Orientation orientation,
  required Size logicalSize,
  bool keyboardVisible = false,
}) {
  // A soft keyboard can transiently shrink the reported view height below its
  // width, flipping MediaQuery.orientation to landscape while the device is
  // physically in portrait (Symptom A2). Never show the rotate overlay while a
  // keyboard inset is up: the user can't rotate to type anyway, and this is the
  // exact window where the orientation reading is untrustworthy.
  if (keyboardVisible) return false;
  if (orientation != Orientation.landscape) return false;
  return logicalSize.shortestSide < AppConstants.portraitLockMaxShortestSide;
}
