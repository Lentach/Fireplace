import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS()
extension type _NavigatorStandalone(JSObject _) {
  external bool? get standalone;
}

class WebPushBridge {
  static const String _serviceWorkerPath = '/web-push-sw.js';
  static const String _serviceWorkerScope = '/web-push-scope/';

  bool get isSupported {
    return web.window.isSecureContext &&
        _navigatorHas('serviceWorker') &&
        _windowHas('Notification');
  }

  /// Whether the platform's "must be standalone PWA" requirement for Web Push
  /// is satisfied (or not applicable).
  ///
  /// Only iOS Safari/WebKit refuses to subscribe a tab to Web Push; it
  /// requires the page to be added to the Home Screen and launched in
  /// standalone display mode. Every other engine (Chrome / Edge / Firefox /
  /// Comet on desktop and Android) can subscribe from a regular tab in any
  /// secure context, so we let them through.
  bool isStandaloneOrNotRequired() {
    if (!_isIOSWebKit()) return true;
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    try {
      if (_NavigatorStandalone(web.window.navigator as JSObject).standalone ==
          true) {
        return true;
      }
    } catch (_) {
      // navigator.standalone is iOS Safari–only; ignore on engines that lack it.
    }
    return false;
  }

  bool _isIOSWebKit() {
    final ua = web.window.navigator.userAgent.toLowerCase();
    if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
      return true;
    }
    // iPadOS 13+ reports a Mac UA but exposes touch points > 1.
    if (ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 1) {
      return true;
    }
    return false;
  }

  String get notificationPermission => web.Notification.permission;

  Future<Map<String, dynamic>?> registerExistingSubscription({
    required String vapidPublicKey,
    String? userAgent,
  }) async {
    if (!isSupported || notificationPermission != 'granted') return null;
    final registration = await _registerServiceWorker();
    final subscription =
        await registration.pushManager.getSubscription().toDart;
    return _toPayload(subscription, userAgent);
  }

  Future<Map<String, dynamic>?> requestSubscriptionFromUserGesture({
    required String vapidPublicKey,
    String? userAgent,
  }) async {
    if (!isSupported) return null;
    final permission = (await web.Notification.requestPermission().toDart).toDart;
    if (permission != 'granted') return null;

    final registration = await _registerServiceWorker();
    var subscription =
        await registration.pushManager.getSubscription().toDart;
    subscription ??=
        await _subscribe(registration, vapidPublicKey);
    return _toPayload(subscription, userAgent);
  }

  Future<String?> unsubscribe() async {
    if (!isSupported) return null;
    final registration = await _registerServiceWorker();
    final subscription =
        await registration.pushManager.getSubscription().toDart;
    if (subscription == null) return null;
    final endpoint = subscription.endpoint;
    await subscription.unsubscribe().toDart;
    return endpoint;
  }

  Future<web.ServiceWorkerRegistration> _registerServiceWorker() {
    return web.window.navigator.serviceWorker
        .register(
          _serviceWorkerPath.toJS,
          web.RegistrationOptions(scope: _serviceWorkerScope),
        )
        .toDart;
  }

  Future<web.PushSubscription> _subscribe(
    web.ServiceWorkerRegistration registration,
    String vapidPublicKey,
  ) {
    final keyBytes = _base64UrlToUint8List(vapidPublicKey);
    return registration.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: keyBytes.toJS,
          ),
        )
        .toDart;
  }

  Map<String, dynamic>? _toPayload(
    web.PushSubscription? subscription,
    String? userAgent,
  ) {
    if (subscription == null) return null;
    final p256dhBuffer = subscription.getKey('p256dh');
    final authBuffer = subscription.getKey('auth');
    if (p256dhBuffer == null || authBuffer == null) {
      return null;
    }

    return {
      'endpoint': subscription.endpoint,
      'keys': {
        'p256dh': _toBase64Url(_bytesFromArrayBuffer(p256dhBuffer)),
        'auth': _toBase64Url(_bytesFromArrayBuffer(authBuffer)),
      },
      'expirationTime': subscription.expirationTime,
      'userAgent': userAgent ?? web.window.navigator.userAgent,
    };
  }

  bool _navigatorHas(String property) =>
      (web.window.navigator as JSObject).hasProperty(property.toJS).toDart;

  bool _windowHas(String property) =>
      (web.window as JSObject).hasProperty(property.toJS).toDart;

  Uint8List _bytesFromArrayBuffer(JSArrayBuffer buffer) =>
      Uint8List.view(buffer.toDart);

  Uint8List _base64UrlToUint8List(String value) {
    final output = base64Url.normalize(value);
    return base64Url.decode(output);
  }

  String _toBase64Url(Uint8List bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  // Tracks whether the SW 'message' listener has been registered.
  static bool _clickListenerRegistered = false;

  /// Register a listener on navigator.serviceWorker 'message' events.
  /// Filters on `type == 'push-notification-click'` and calls [handler] with the
  /// conversationId (null if absent). Safe to call multiple times — only registers once.
  void listenForNotificationClicks(
      void Function(int? conversationId) handler) {
    if (_clickListenerRegistered) return;
    _clickListenerRegistered = true;

    (web.window.navigator.serviceWorker as JSObject).callMethod<JSAny?>(
      'addEventListener'.toJS,
      'message'.toJS,
      ((JSObject event) {
        try {
          final data = event.getProperty<JSObject?>('data'.toJS);
          if (data == null) return;
          final type = data.getProperty<JSString?>('type'.toJS)?.toDart;
          if (type != 'push-notification-click') return;
          final convIdJs = data.getProperty<JSAny?>('conversationId'.toJS);
          int? convId;
          if (convIdJs != null) {
            final raw = convIdJs.dartify();
            if (raw is num) convId = raw.toInt();
          }
          handler(convId);
        } catch (_) {}
      }).toJS,
    );
  }

  /// Post a badge-update message to the controlling SW.
  /// On iOS, SW context is required for badge persistence after WebView close.
  void updateBadgeViaSw(int count) {
    try {
      final controller = web.window.navigator.serviceWorker.controller;
      if (controller == null) return;
      if (count <= 0) {
        controller.postMessage({'type': 'clear-badge'}.jsify());
      } else {
        controller.postMessage({'type': 'set-badge', 'count': count}.jsify());
      }
    } catch (_) {}
  }
}

WebPushBridge createWebPushBridge() => WebPushBridge();
