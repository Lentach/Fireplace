import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

/// Above this fraction of layout height, [MediaQuery.viewInsets.bottom] on mobile
/// web is treated as phantom (Android Chrome can report huge values on focus).
const double kWebPhantomKeyboardInsetFraction = 0.45;

/// Caps a bottom inset so phantom values (common on Android Chrome Web) do not lift the UI.
double capKeyboardInset(double inset, double layoutHeight) {
  if (inset <= 0) return inset;
  final cap = layoutHeight * kWebPhantomKeyboardInsetFraction;
  return inset > cap ? cap : inset;
}

/// Bottom inset for chat when [Scaffold.resizeToAvoidBottomInset] is false on web.
double effectiveChatKeyboardInset(MediaQueryData mediaQuery) {
  final raw = mediaQuery.viewInsets.bottom;
  if (!kIsWeb || raw <= 0) return raw;
  return capKeyboardInset(raw, mediaQuery.size.height);
}
