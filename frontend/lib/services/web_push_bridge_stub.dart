/// Non-web stub — Web Push is only used on `dart:library.html` builds.
class WebPushBridge {
  bool get isSupported => false;

  bool isStandaloneOrNotRequired() => false;

  String get notificationPermission => 'denied';

  Future<Map<String, dynamic>?> registerExistingSubscription({
    required String vapidPublicKey,
    String? userAgent,
  }) async =>
      null;

  Future<Map<String, dynamic>?> requestSubscriptionFromUserGesture({
    required String vapidPublicKey,
    String? userAgent,
  }) async =>
      null;

  Future<String?> unsubscribe() async => null;

  void listenForNotificationClicks(
      void Function(int? conversationId) handler) {}
}

WebPushBridge createWebPushBridge() => WebPushBridge();
