import 'badging_bridge_stub.dart' if (dart.library.html) 'badging_bridge_web.dart';
import 'push_sw_channel_stub.dart'
    if (dart.library.html) 'push_sw_channel_web.dart';

/// Clears the OS PWA app icon badge. Call on **logout** / cleared session only —
/// not when [MainShell] disposes because the user closed the app (unread may remain).
/// Routed through the push SW (single badge writer); window Badging API fallback.
Future<void> clearPwaAppBadgeOnLogout() async {
  final delivered =
      await createPushSwChannel().postMessage(const {'type': 'clear-badge'});
  if (delivered) return;
  final bridge = createBadgingBridge();
  await bridge.clearBadge();
}
