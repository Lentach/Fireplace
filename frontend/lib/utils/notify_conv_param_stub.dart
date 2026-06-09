/// Stub — returns null on non-web platforms (Android native deep-links use FCM path).
int? consumeNotifyConvParam() => null;

/// No-op on non-web platforms.
void stripNotifyConvParam() {}
