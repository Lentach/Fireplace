import 'package:firebase_messaging/firebase_messaging.dart';

/// Web builds: unused (FCM background handler not registered). VM/io builds use
/// [android_fcm_local_notifications.firebaseMessagingBackgroundHandler].
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}
