import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

const String _androidChannelId = 'fireplace_messages';
const String _androidChannelName = 'Messages';
const String _androidChannelDescription = 'Alerts for new encrypted chat messages';

final FlutterLocalNotificationsPlugin _mainIsolateNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final FlutterLocalNotificationsPlugin _backgroundIsolateNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void Function(int conversationId)? _conversationTapHandler;

bool _mainIsolatePluginReady = false;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool _backgroundIsolateReady = false;

/// Mutable tap target — updated each login so logout does not keep stale closures.
void setAndroidNotificationConversationTapHandler(
  void Function(int conversationId)? handler,
) {
  _conversationTapHandler = handler;
}

/// Required FCM background entrypoint (separate isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  if (!_isAndroid) return;

  if (!_backgroundIsolateReady) {
    await _backgroundIsolateNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_fireplace'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    final android = _backgroundIsolateNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: _androidChannelDescription,
        importance: Importance.high,
      ),
    );
    _backgroundIsolateReady = true;
  }

  await showFireplaceMessageNotificationWithPlugin(
    plugin: _backgroundIsolateNotificationsPlugin,
    data: message.data,
  );
}

/// Main isolate: plugin + channel + tap routing via [_conversationTapHandler].
Future<void> initAndroidFcmLocalNotificationsOnMainIsolate() async {
  if (!_isAndroid || _mainIsolatePluginReady) return;

  await _mainIsolateNotificationsPlugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      final raw = response.payload;
      if (raw == null || raw.isEmpty) return;
      final id = int.tryParse(raw);
      if (id != null) _conversationTapHandler?.call(id);
    },
  );

  final android = _mainIsolateNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      description: _androidChannelDescription,
      importance: Importance.high,
    ),
  );

  _mainIsolatePluginReady = true;
}

Future<void> showFireplaceMessageNotificationWithPlugin({
  required FlutterLocalNotificationsPlugin plugin,
  required Map<String, dynamic> data,
}) async {
  if (data['type'] != 'new_message') return;

  final convRaw = data['conversationId'];
  final conversationId = convRaw != null ? int.tryParse(convRaw.toString()) : null;

  final countRaw = data['messageCount'];
  final messageCount = countRaw != null ? int.tryParse(countRaw.toString()) : null;

  final body = messageCount != null && messageCount > 1
      ? 'You have $messageCount new messages'
      : 'You have a new message';

  final notificationId = conversationId ?? 0;
  final tag =
      conversationId != null ? 'conversation-$conversationId' : 'fireplace-message';

  final androidDetails = AndroidNotificationDetails(
    _androidChannelId,
    'Fireplace',
    channelDescription: _androidChannelDescription,
    importance: Importance.high,
    priority: Priority.high,
    // Status-bar small icon: monochrome white-on-transparent flame
    // (res/drawable-*/ic_stat_fireplace.png). A full-colour icon here renders
    // as a white square in the status bar.
    icon: '@drawable/ic_stat_fireplace',
    tag: tag,
  );

  await plugin.show(
    id: notificationId,
    title: 'Fireplace',
    body: body,
    notificationDetails: NotificationDetails(android: androidDetails),
    payload: conversationId?.toString(),
  );
}

/// Cold start: user tapped a local notification while the app was terminated.
Future<void> deliverPendingLocalNotificationTapIfAny({
  required void Function(int conversationId) onConversationId,
}) async {
  if (!_isAndroid || !_mainIsolatePluginReady) return;

  final details =
      await _mainIsolateNotificationsPlugin.getNotificationAppLaunchDetails();
  final payload = details?.notificationResponse?.payload;
  if (payload == null || payload.isEmpty) return;
  final id = int.tryParse(payload);
  if (id != null) onConversationId(id);
}

void handleFcmRemoteMessageOpen(
  RemoteMessage message, {
  required void Function(int conversationId) onConversationId,
}) {
  final convRaw = message.data['conversationId'];
  final conversationId =
      convRaw != null ? int.tryParse(convRaw.toString()) : null;
  if (conversationId != null) onConversationId(conversationId);
}
