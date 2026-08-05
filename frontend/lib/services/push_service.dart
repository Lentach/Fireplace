import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../push_android_stub.dart'
    if (dart.library.io) 'android_fcm_local_notifications.dart' as push_android;
import '../utils/pending_deep_link_stub.dart'
    if (dart.library.html) '../utils/pending_deep_link_web.dart';
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
/// [android_fcm_local_notifications.dart]); tap routes via [onNavigateToConversation].
class PushService {
  final ApiService _api;
  final WebPushBridge _webPushBridge = createWebPushBridge();

  StreamSubscription<RemoteMessage>? _androidFcmOpenedSubscription;

  /// Set by main.dart from the `notify_conv` URL param before initialize() is called.
  /// Drained once by ConnectionProvider._onSocketReady().
  int? coldStartConversationId;

  // VAPID public key for web push, injected via the WEB_PUSH_VAPID_PUBLIC_KEY
  // dart-define at build time (deploy-web.ps1 passes it). NO hardcoded fallback:
  // an empty key makes web-push subscribe fail loudly instead of silently
  // subscribing to a stale/wrong key (which causes 400 delivery + the backend
  // pruning the subscription). MUST match the backend VAPID pair (CLAUDE.md §3, §5).
  static const String _vapidKey = String.fromEnvironment(
    'WEB_PUSH_VAPID_PUBLIC_KEY',
    defaultValue: '',
  );

  PushService(this._api);

  /// Initialize push notifications and register the FCM token with the server.
  /// Call after WebSocket connect so the user is authenticated.
  /// [jwtToken] is the current user's JWT for the backend API call.
  ///
  /// [currentJwtToken] supplies the JWT that is current AT CALL TIME. The
  /// `onTokenRefresh` listener below outlives many token rotations (initialize
  /// runs once per app run), so capturing [jwtToken] there registered a rotated
  /// device token with a stale JWT — 401, swallowed, push silently dead until
  /// the next launch.
  ///
  /// [onNavigateToConversation]: notification tap routing (Android FCM + web push).
  Future<void> initialize(
    String jwtToken, {
    String? Function()? currentJwtToken,
    void Function(int conversationId)? onNavigateToConversation,
  }) async {
    if (kIsWeb) {
      await _registerExistingWebSubscription(jwtToken);
      if (onNavigateToConversation != null) {
        _webPushBridge.listenForNotificationClicks((convId) {
          // Click handled live — drop the SW's IndexedDB fallback record so it
          // cannot re-trigger navigation on the next cold start.
          clearPendingNotificationDeepLink().ignore();
          if (convId != null) onNavigateToConversation(convId);
        });
      }
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
        vapidKey: null,
      );
      if (fcmToken == null) return;

      final platform = _currentPlatform();
      await _api.registerFcmToken(jwtToken, fcmToken, platform);

      // Handle token rotation — Firebase periodically refreshes tokens
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        final token = currentJwtToken?.call() ?? jwtToken;
        _api.registerFcmToken(token, newToken, platform).catchError((error) {
          debugPrint('[PushService] FCM token re-registration failed: $error');
        });
      });

      if (defaultTargetPlatform == TargetPlatform.android) {
        await push_android.initAndroidFcmLocalNotificationsOnMainIsolate();
        push_android.setAndroidNotificationConversationTapHandler(
          onNavigateToConversation,
        );

        await push_android.deliverPendingLocalNotificationTapIfAny(
          onConversationId: (id) {
            onNavigateToConversation?.call(id);
          },
        );

        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          push_android.handleFcmRemoteMessageOpen(
            initial,
            onConversationId: (id) =>
                onNavigateToConversation?.call(id),
          );
        }

        await _androidFcmOpenedSubscription?.cancel();
        _androidFcmOpenedSubscription =
            FirebaseMessaging.onMessageOpenedApp.listen((message) {
          push_android.handleFcmRemoteMessageOpen(
            message,
            onConversationId: (id) =>
                onNavigateToConversation?.call(id),
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
        vapidKey: null,
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
