import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';

bool shouldShowRotateOverlay({
  required Orientation orientation,
  required Size logicalSize,
}) {
  if (orientation != Orientation.landscape) return false;
  return logicalSize.shortestSide < AppConstants.portraitLockMaxShortestSide;
}
