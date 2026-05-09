import 'dart:js_util' as js_util;

/// Web implementation of the [Badging API](https://developer.mozilla.org/en-US/docs/Web/API/Badging_API).
class BadgingBridge {
  bool get isSupported {
    final nav = js_util.globalThis.navigator;
    return js_util.hasProperty(nav, 'setAppBadge') &&
        js_util.hasProperty(nav, 'clearAppBadge');
  }

  Future<void> setBadgeCount(int cappedNonZero) async {
    if (!isSupported || cappedNonZero <= 0) return;
    try {
      final nav = js_util.globalThis.navigator;
      final result = js_util.callMethod(nav, 'setAppBadge', [cappedNonZero]);
      await js_util.promiseToFuture(result);
    } catch (_) {
      // Permission / inactive document / platform policy — ignore.
    }
  }

  Future<void> clearBadge() async {
    if (!isSupported) return;
    try {
      final nav = js_util.globalThis.navigator;
      final result = js_util.callMethod(nav, 'clearAppBadge', []);
      await js_util.promiseToFuture(result);
    } catch (_) {
      // Ignore — same as setBadgeCount.
    }
  }
}

BadgingBridge createBadgingBridge() => BadgingBridge();
