import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../push_android_stub.dart'
    if (dart.library.io) 'android_fcm_local_notifications.dart' as push_android;
import 'api_service.dart';
import 'web_push_bridge_stub.dart'
    if (dart.library.html) 'web_push_bridge_web.dart';

enum WebPushRequestStatus {
  subscribed,
  denied,
  unsupported,
  requiresStandalone,
  noChange,
  failed,
}

class WebPushRequestResult {
  final WebPushRequestStatus status;
  final String? details;

  const WebPushRequestResult(this.status, {this.details});
}

/// Handles FCM push notification registration and token lifecycle.
///
/// Privacy strategy (Signal/Wire-style): FCM only receives { type: 'new_message' }.
/// Message content is NEVER sent through FCM — the app wakes up and fetches
/// the message from your own server via WebSocket.
///
/// Android: data messages show a grouped local notification (see
/// [android_fcm_local_notifications.dart]); tap routes via [onAndroidNavigateToConversation].
class PushService {
  final ApiService _api;
  final WebPushBridge _webPushBridge = createWebPushBridge();

  StreamSubscription<RemoteMessage>? _androidFcmOpenedSubscription;

  // VAPID key for web push — get from:
  // Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
  // → Generate key pair → copy the public key.
  // TODO: Replace with your real VAPID key.
  static const String _vapidKey = String.fromEnvironment(
    'WEB_PUSH_VAPID_PUBLIC_KEY',
    defaultValue:
        'BOkbC_6t7ScCiTLyuLyM0wEG3TnXfpQaAMwZUeJHuWhtt7HVr0u3zG60xm4kqqhnNzuHZco-8h0Nt_WRYRZrZHU',
  );

  PushService(this._api);

  /// Initialize push notifications and register the FCM token with the server.
  /// Call after WebSocket connect so the user is authenticated.
  /// [jwtToken] is the current user's JWT for the backend API call.
  ///
  /// [onAndroidNavigateToConversation]: notification / FCM open routing (Android only).
  Future<void> initialize(
    String jwtToken, {
    void Function(int conversationId)? onAndroidNavigateToConversation,
  }) async {
    if (kIsWeb) {
      await _registerExistingWebSubscription(jwtToken);
      return;
    }
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

      if (defaultTargetPlatform == TargetPlatform.android) {
        await push_android.initAndroidFcmLocalNotificationsOnMainIsolate();
        push_android.setAndroidNotificationConversationTapHandler(
          onAndroidNavigateToConversation,
        );

        await push_android.deliverPendingLocalNotificationTapIfAny(
          onConversationId: (id) {
            onAndroidNavigateToConversation?.call(id);
          },
        );

        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          push_android.handleFcmRemoteMessageOpen(
            initial,
            onConversationId: (id) =>
                onAndroidNavigateToConversation?.call(id),
          );
        }

        await _androidFcmOpenedSubscription?.cancel();
        _androidFcmOpenedSubscription =
            FirebaseMessaging.onMessageOpenedApp.listen((message) {
          push_android.handleFcmRemoteMessageOpen(
            message,
            onConversationId: (id) =>
                onAndroidNavigateToConversation?.call(id),
          );
        });
      }
    } catch (_) {
      // Push setup failed (Firebase not configured, no permission, etc.) — silently ignored
    }
  }

  /// Unregister FCM token from the server and delete it from Firebase.
  /// Call on logout BEFORE clearing the JWT.
  Future<void> unregister(String jwtToken) async {
    if (kIsWeb) {
      await _unregisterWebPush(jwtToken);
      return;
    }
    try {
      await _androidFcmOpenedSubscription?.cancel();
      _androidFcmOpenedSubscription = null;
      push_android.setAndroidNotificationConversationTapHandler(null);

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

  Future<WebPushRequestResult> requestWebPushFromUserGesture(
    String jwtToken,
  ) async {
    if (!kIsWeb) {
      return const WebPushRequestResult(WebPushRequestStatus.unsupported);
    }
    if (!_webPushBridge.isSupported) {
      return const WebPushRequestResult(WebPushRequestStatus.unsupported);
    }
    if (!_webPushBridge.isStandaloneOrNotRequired()) {
      return const WebPushRequestResult(WebPushRequestStatus.requiresStandalone);
    }

    try {
      final payload =
          await _webPushBridge.requestSubscriptionFromUserGesture(
            vapidPublicKey: _vapidKey,
          );
      if (payload == null) {
        final permission = _webPushBridge.notificationPermission;
        if (permission == 'denied') {
          return const WebPushRequestResult(WebPushRequestStatus.denied);
        }
        return const WebPushRequestResult(WebPushRequestStatus.noChange);
      }
      await _api.registerWebPushSubscription(jwtToken, payload);
      return const WebPushRequestResult(WebPushRequestStatus.subscribed);
    } catch (e) {
      return WebPushRequestResult(
        WebPushRequestStatus.failed,
        details: e.toString(),
      );
    }
  }

  Future<void> _registerExistingWebSubscription(String jwtToken) async {
    if (!_webPushBridge.isSupported) return;
    if (_webPushBridge.notificationPermission != 'granted') return;

    try {
      final payload = await _webPushBridge.registerExistingSubscription(
        vapidPublicKey: _vapidKey,
      );
      if (payload == null) return;
      await _api.registerWebPushSubscription(jwtToken, payload);
    } catch (_) {
      // Best-effort only on startup/reconnect.
    }
  }

  Future<void> _unregisterWebPush(String jwtToken) async {
    if (!_webPushBridge.isSupported) return;
    try {
      final endpoint = await _webPushBridge.unsubscribe();
      if (endpoint != null) {
        await _api.removeWebPushSubscription(jwtToken, endpoint);
      }
    } catch (_) {
      // Best-effort — don't block logout.
    }
  }

  static String _currentPlatform() {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'android'; // Android or any other native platform
  }
}
