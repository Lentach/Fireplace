import 'package:firebase_messaging/firebase_messaging.dart';

/// Web stub — real implementations in `services/android_fcm_local_notifications.dart` (dart:io builds).

Future<void> initAndroidFcmLocalNotificationsOnMainIsolate() async {}

void setAndroidNotificationConversationTapHandler(
  void Function(int conversationId)? handler,
) {}

Future<void> deliverPendingLocalNotificationTapIfAny({
  required void Function(int conversationId) onConversationId,
}) async {}

void handleFcmRemoteMessageOpen(
  RemoteMessage message, {
  required void Function(int conversationId) onConversationId,
}) {}
