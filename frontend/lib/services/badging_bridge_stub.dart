/// Non-web / unsupported engine — Badging API not used.
class BadgingBridge {
  bool get isSupported => false;

  Future<void> setBadgeCount(int cappedNonZero) async {}

  Future<void> clearBadge() async {}
}

BadgingBridge createBadgingBridge() => BadgingBridge();
