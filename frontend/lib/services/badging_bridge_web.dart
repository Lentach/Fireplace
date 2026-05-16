import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool _navigatorHasBadgingApi(String property) =>
    (web.window.navigator as JSObject).hasProperty(property.toJS).toDart;

/// Web implementation of the [Badging API](https://developer.mozilla.org/en-US/docs/Web/API/Badging_API).
class BadgingBridge {
  bool get isSupported =>
      _navigatorHasBadgingApi('setAppBadge') &&
      _navigatorHasBadgingApi('clearAppBadge');

  /// Sets the app icon badge to [cappedNonZero] (must be > 0). Uses `setAppBadge(n)` — required
  /// for **Safari / iOS PWA**, which often ignore `setAppBadge()` with no arguments.
  Future<void> setBadgeCount(int cappedNonZero) async {
    if (!isSupported || cappedNonZero <= 0) return;
    try {
      await web.window.navigator.setAppBadge(cappedNonZero).toDart;
    } catch (_) {
      // Permission / inactive document / platform policy — ignore.
    }
  }

  Future<void> clearBadge() async {
    if (!isSupported) return;
    try {
      await web.window.navigator.clearAppBadge().toDart;
    } catch (_) {
      // Ignore — same as setBadgeCount.
    }
  }
}

BadgingBridge createBadgingBridge() => BadgingBridge();
