import 'package:web/web.dart' as web;

/// iOS Safari / WebKit (including iPadOS 13+ Mac UA with touch).
bool isIOSWebKit() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
    return true;
  }
  if (ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 1) {
    return true;
  }
  return false;
}
