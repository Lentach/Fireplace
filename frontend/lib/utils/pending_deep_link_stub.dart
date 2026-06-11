/// Stub — non-web platforms deep-link via the FCM path, not IndexedDB.
Future<int?> consumePendingNotificationDeepLink() async => null;

/// No-op on non-web platforms.
Future<void> clearPendingNotificationDeepLink() async {}
