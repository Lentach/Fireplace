import 'dart:math' as math;

/// Android Chrome Web can report an oversized [viewInsetsBottom] while the
/// visual viewport shows a smaller keyboard. Prefer the smaller trustworthy signal.
double resolveAndroidChromeWebKeyboardInset({
  required double viewInsetsBottom,
  required double layoutHeight,
  double? visualViewportKeyboardInset,
}) {
  if (layoutHeight <= 0) return 0;

  final mq = viewInsetsBottom.clamp(0.0, layoutHeight);
  final vv = (visualViewportKeyboardInset ?? 0).clamp(0.0, layoutHeight);
  if (mq <= 0 && vv <= 0) return 0;

  const suspiciousFraction = 0.45;
  final mqSuspicious = mq > layoutHeight * suspiciousFraction;

  if (mqSuspicious) {
    if (vv > 0) return vv;
    // visualViewport can lag MediaQuery by a frame; cap phantom mq instead of 0.
    return math.min(mq, layoutHeight * suspiciousFraction);
  }

  if (vv > 0) return math.max(mq, vv);
  return mq;
}

/// Bottom spacer under the composer (see [ChatInputBar]).
double composerBottomInteractivePadding({
  required bool androidChromeWebComposerLift,
  required bool keyboardVisible,
  required double viewInsetsBottom,
  required double layoutHeight,
  required double? visualViewportKeyboardInset,
  required double bottomSystemInset,
  required bool webMobileFallbackNeeded,
  required double webMobileFallbackInset,
}) {
  if (keyboardVisible && androidChromeWebComposerLift) {
    return resolveAndroidChromeWebKeyboardInset(
      viewInsetsBottom: viewInsetsBottom,
      layoutHeight: layoutHeight,
      visualViewportKeyboardInset: visualViewportKeyboardInset,
    );
  }

  if (keyboardVisible) return 0;

  const additionalBottomSpacing = 16.0;
  final needsErgonomicBuffer = bottomSystemInset > 0;
  if (needsErgonomicBuffer) {
    return bottomSystemInset + additionalBottomSpacing;
  }
  if (webMobileFallbackNeeded) return webMobileFallbackInset;
  return 0;
}
