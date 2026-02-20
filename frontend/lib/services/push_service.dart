import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'api_service.dart';

/// Handles FCM push notification registration and token lifecycle.
///
/// Privacy strategy (Signal/Wire-style): FCM only receives { type: 'new_message' }.
/// Message content is NEVER sent through FCM — the app wakes up and fetches
/// the message from your own server via WebSocket.
class PushService {
  final ApiService _api;

  // VAPID key for web push — get from:
  // Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
  // → Generate key pair → copy the public key.
  // TODO: Replace with your real VAPID key.
  static const String _vapidKey =
      'BOkbC_6t7ScCiTLyuLyM0wEG3TnXfpQaAMwZUeJHuWhtt7HVr0u3zG60xm4kqqhnNzuHZco-8h0Nt_WRYRZrZHU';

  PushService(this._api);

  /// Initialize push notifications and register the FCM token with the server.
  /// Call after WebSocket connect so the user is authenticated.
  /// [jwtToken] is the current user's JWT for the backend API call.
  Future<void> initialize(String jwtToken) async {
    try {
      // Request permission (Android 13+, iOS always, Web when called)
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return; // User denied
      }

      final fcmToken = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? _vapidKey : null,
      );
      if (fcmToken == null) return;

      final platform = _currentPlatform();
      await _api.registerFcmToken(jwtToken, fcmToken, platform);

      // Handle token rotation — Firebase periodically refreshes tokens
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _api.registerFcmToken(jwtToken, newToken, platform).catchError((_) {});
      });

      // Foreground: do not show notification — user has active tab, WebSocket already delivered the message
      FirebaseMessaging.onMessage.listen((_) {});
    } catch (_) {
      // Push setup failed (Firebase not configured, no permission, etc.) — silently ignored
    }
  }

  /// Unregister FCM token from the server and delete it from Firebase.
  /// Call on logout BEFORE clearing the JWT.
  Future<void> unregister(String jwtToken) async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? _vapidKey : null,
      );
      if (fcmToken != null) {
        await _api.removeFcmToken(jwtToken, fcmToken);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Best-effort — don't block logout
    }
  }

  static String _currentPlatform() {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'android'; // Android or any other native platform
  }
}
