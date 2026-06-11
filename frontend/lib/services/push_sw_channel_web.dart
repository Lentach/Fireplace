import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Posts messages to the **push** service worker (scope `/web-push-scope/`).
///
/// MUST NOT use `navigator.serviceWorker.ready` or `.controller` — both
/// resolve against the page's own scope (`/`), i.e. the Flutter app SW, which
/// has no badge/tray message handlers. That mis-routing was the root cause of
/// the never-clearing iOS badge. Only `getRegistration('/web-push-scope/')`
/// reaches the push SW.
class PushSwChannel {
  static const String _pushSwScope = '/web-push-scope/';

  /// Returns `true` when the message was handed to the push SW; `false` when
  /// the push SW is not registered/active (e.g. push permission never granted)
  /// so the caller can fall back to a window-context write where one exists.
  Future<bool> postMessage(Map<String, Object?> message) async {
    try {
      final regAny = await web.window.navigator.serviceWorker
          .getRegistration(_pushSwScope)
          .toDart;
      if (regAny.isUndefinedOrNull) return false;
      final active = (regAny as web.ServiceWorkerRegistration).active;
      if (active == null) return false;
      active.postMessage(message.jsify());
      return true;
    } catch (_) {
      return false;
    }
  }
}

PushSwChannel createPushSwChannel() => PushSwChannel();
