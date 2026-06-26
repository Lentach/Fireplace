import 'dart:ui' show Color;

import 'web_ios_composer_focus_mask_stub.dart'
    if (dart.library.html) 'web_ios_composer_focus_mask_web.dart' as impl;

/// Converts a Flutter [Color] to a CSS `#rrggbb` hex string. Alpha is dropped —
/// the focus mask must be fully opaque to hide the transient underneath.
String composerMaskCssColor(Color color) {
  String hex(double channel) =>
      (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${hex(color.r)}${hex(color.g)}${hex(color.b)}';
}

/// Paints a solid [cssColor] mask over the whole scene to hide the iOS-WebKit
/// composer-focus transient (the keyboard-open document-scroll + visual-viewport
/// pan "flash"), then fades it out once the viewport has settled (the pin has
/// reconciled: keyboard up + `offsetTop` back to ~0) or after a safety timeout.
///
/// A full-scene solid fill needs no frame-perfect tracking, so the GPU-compositor
/// lag that defeats the pin's reactive reset (it can only *undo* the jump a frame
/// late, never prevent it) stops mattering — the jump still happens, invisibly,
/// underneath. Scoped + iOS-WebKit-only + reverted on blur — NOT a global lock.
/// No-op off iOS WebKit / off web.
void showComposerFocusMask(String cssColor) =>
    impl.showComposerFocusMask(cssColor);

/// Immediately removes the focus mask (blur / drag-away / dispose). No-op when no
/// mask is showing or off iOS WebKit / off web.
void hideComposerFocusMask() => impl.hideComposerFocusMask();

/// TEMP diagnostic: one-line live DOM state of the focus mask, for the jump_probe
/// overlay. Empty string off web. Remove with the probe once the bug is fixed.
String composerFocusMaskDiag() => impl.composerFocusMaskDiag();
