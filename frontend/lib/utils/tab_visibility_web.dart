import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Fires when the browser tab becomes hidden or visible (non-PWA tabs included).
StreamSubscription<html.Event>? registerTabVisibilityListener(
  void Function(bool isVisible) onChanged,
) {
  void handler(html.Event _) {
    onChanged(html.document.visibilityState == 'visible');
  }

  final sub = html.document.onVisibilityChange.listen(handler);
  onChanged(html.document.visibilityState == 'visible');
  return sub;
}
