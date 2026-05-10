import 'badging_bridge_stub.dart' if (dart.library.html) 'badging_bridge_web.dart';

/// Clears the OS PWA app icon badge. Call on **logout** / cleared session only —
/// not when [MainShell] disposes because the user closed the app (unread may remain).
Future<void> clearPwaAppBadgeOnLogout() async {
  final bridge = createBadgingBridge();
  await bridge.clearBadge();
}
