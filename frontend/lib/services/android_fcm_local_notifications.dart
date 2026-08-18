import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


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
      // No options: the background isolate must also use the NATIVE default
      // app (google-services.json), not the placeholder Dart-side options —
      // see main.dart. This isolate can start before main() ever ran.
      await Firebase.initializeApp();
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
  // Phase 0a takeover alarm: content-free security notice (see
  // push-notifications.service.ts notifyIdentityChanged). Same wording rule
  // as the PWA service worker: this fires on legitimate reinstalls/new
  // sign-ins too, so it must not scream "hacked".
  if (data['type'] == 'identity_changed') {
    const androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      'Fireplace',
      channelDescription: _androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_fireplace',
      tag: 'identity-changed',
    );
    await plugin.show(
      // Fixed id well outside the conversation-id space so it replaces
      // itself and never collides with a message notification.
      id: 0x40000000,
      title: 'Fireplace',
      body:
          'New encryption keys on your account — usually a new device or '
          'browser sign-in. Open the app to review.',
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
    return;
  }
  // Phase 0b reset ceremony: a countdown toward new account keys started, or
  // was cancelled. Push is the only channel that reaches a closed app, which
  // is what makes the delay meaningful. Both share one tag/id so the cancel
  // notice REPLACES the warning instead of leaving a stale "act now" card.
  final resetType = data['type'];
  if (resetType == 'identity_reset_pending' ||
      resetType == 'identity_reset_cancelled') {
    final pending = resetType == 'identity_reset_pending';
    final androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      'Fireplace',
      channelDescription: _androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_fireplace',
      tag: 'identity-reset',
      ongoing: pending,
    );
    await plugin.show(
      // Fixed id, distinct from the replacement alarm's, well outside the
      // conversation-id space.
      id: 0x40000001,
      title: 'Fireplace',
      body: pending
          ? 'Someone asked to reset your account encryption keys. If this '
                'was not you, open the app and cancel it.'
          : 'The encryption key reset was cancelled.',
      notificationDetails: NotificationDetails(android: androidDetails),
    );
    return;
  }
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
