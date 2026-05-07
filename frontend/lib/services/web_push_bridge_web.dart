import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

class WebPushBridge {
  static const String _serviceWorkerPath = '/web-push-sw.js';
  static const String _serviceWorkerScope = '/web-push-scope/';

  bool get isSupported {
    return html.window.isSecureContext == true &&
        html.window.navigator.serviceWorker != null &&
        html.Notification.supported;
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
    if (html.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    try {
      final dynamic nav = html.window.navigator;
      if (nav.standalone == true) return true;
    } catch (_) {
      // navigator.standalone is iOS Safari–only; ignore on engines that lack it.
    }
    return false;
  }

  bool _isIOSWebKit() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
      return true;
    }
    // iPadOS 13+ reports a Mac UA but exposes touch points > 1.
    if (ua.contains('macintosh')) {
      try {
        final dynamic nav = html.window.navigator;
        final mtp = nav.maxTouchPoints;
        if (mtp is int && mtp > 1) return true;
      } catch (_) {
        // Older Safari without maxTouchPoints — fall through.
      }
    }
    return false;
  }

  String get notificationPermission {
    return html.Notification.permission ?? 'default';
  }

  Future<Map<String, dynamic>?> registerExistingSubscription({
    required String vapidPublicKey,
    String? userAgent,
  }) async {
    if (!isSupported || notificationPermission != 'granted') return null;
    final registration = await _registerServiceWorker();
    final subscription = await _getExistingSubscription(registration);
    return _toPayload(subscription, userAgent);
  }

  Future<Map<String, dynamic>?> requestSubscriptionFromUserGesture({
    required String vapidPublicKey,
    String? userAgent,
  }) async {
    if (!isSupported) return null;
    final permission = await html.Notification.requestPermission();
    if (permission != 'granted') return null;

    final registration = await _registerServiceWorker();
    Object? subscription = await _getExistingSubscription(registration);
    subscription ??= await _subscribe(registration, vapidPublicKey);
    return _toPayload(subscription, userAgent);
  }

  Future<String?> unsubscribe() async {
    if (!isSupported) return null;
    final registration = await _registerServiceWorker();
    final subscription = await _getExistingSubscription(registration);
    if (subscription == null) return null;
    final endpoint = js_util.getProperty(subscription, 'endpoint') as String?;
    await js_util.promiseToFuture<dynamic>(
      js_util.callMethod(subscription, 'unsubscribe', const []),
    );
    return endpoint;
  }

  Future<html.ServiceWorkerRegistration> _registerServiceWorker() {
    return html.window.navigator.serviceWorker!
        .register(_serviceWorkerPath, {'scope': _serviceWorkerScope});
  }

  /// Reads an existing PushSubscription via raw js_util.
  ///
  /// `dart:html` types `PushManager.getSubscription()` as
  /// `Future<PushSubscription>` (non-nullable), but the underlying JS API
  /// legitimately resolves to `null` when no subscription exists. Awaiting
  /// the typed Future then throws `'Null' is not a subtype of FutureOr<PushSubscription>`.
  /// Calling through `js_util.promiseToFuture<dynamic>` returns a
  /// `Future<dynamic>` that can hold null safely.
  Future<Object?> _getExistingSubscription(
    html.ServiceWorkerRegistration registration,
  ) async {
    final pushManager = js_util.getProperty(registration, 'pushManager');
    final result = await js_util.promiseToFuture<dynamic>(
      js_util.callMethod(pushManager, 'getSubscription', const []),
    );
    return result as Object?;
  }

  Future<Object?> _subscribe(
    html.ServiceWorkerRegistration registration,
    String vapidPublicKey,
  ) async {
    final pushManager = js_util.getProperty(registration, 'pushManager');
    final options = js_util.jsify({
      'userVisibleOnly': true,
      'applicationServerKey': _base64UrlToUint8List(vapidPublicKey),
    });
    final result = await js_util.promiseToFuture<dynamic>(
      js_util.callMethod(pushManager, 'subscribe', [options]),
    );
    return result as Object?;
  }

  Map<String, dynamic>? _toPayload(Object? subscription, String? userAgent) {
    if (subscription == null) return null;
    final endpoint = js_util.getProperty(subscription, 'endpoint') as String?;
    final p256dhBuffer =
        js_util.callMethod(subscription, 'getKey', ['p256dh']) as ByteBuffer?;
    final authBuffer =
        js_util.callMethod(subscription, 'getKey', ['auth']) as ByteBuffer?;
    if (endpoint == null || p256dhBuffer == null || authBuffer == null) {
      return null;
    }
    final expirationTime = js_util.getProperty(subscription, 'expirationTime');

    return {
      'endpoint': endpoint,
      'keys': {
        'p256dh': _toBase64Url(Uint8List.view(p256dhBuffer)),
        'auth': _toBase64Url(Uint8List.view(authBuffer)),
      },
      'expirationTime': expirationTime,
      'userAgent': userAgent ?? html.window.navigator.userAgent,
    };
  }

  Uint8List _base64UrlToUint8List(String value) {
    final output = base64Url.normalize(value);
    return base64Url.decode(output);
  }

  String _toBase64Url(Uint8List bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

WebPushBridge createWebPushBridge() => WebPushBridge();
