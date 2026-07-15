/// Application-wide constants. Prefer these over magic numbers.
class AppConstants {
  AppConstants._();

  /// Layout breakpoint: width >= this = desktop (master-detail), below = mobile (stacked)
  static const double layoutBreakpointDesktop = 600;

  /// Shortest logical side below this → show rotate overlay in landscape (phones/tablets).
  static const double portraitLockMaxShortestSide = 900;

  /// Delay before re-fetching conversations on connect (handles slow initial response)
  static const Duration conversationsRefreshDelay = Duration(milliseconds: 500);

  /// Default number of messages loaded per page
  static const int messagePageSize = 50;

  /// Max UTF-8 byte size of the JSON-encoded E2E envelope for a sendable
  /// message. The server caps the resulting base64 ciphertext
  /// (`encryptedContent`) at 65536 chars; base64 is ~4/3 of the Signal
  /// ciphertext (the envelope plus Signal/prekey overhead). Budgeting the
  /// ENVELOPE bytes (via `isMessageWithinByteLimit`) accounts for JSON escaping
  /// and multi-byte emoji — a raw character/byte count would not.
  static const int maxEnvelopeBytes = 45000;

  /// A TEXT message longer than this many wrapped lines collapses in the chat
  /// bubble behind a "Read more" toggle so one long message cannot fill the
  /// screen (Telegram-parity). Tapping expands to the full text.
  static const int maxCollapsedMessageLines = 12;

  /// WebSocket reconnection
  static const int reconnectMaxAttempts = 5;
  static const Duration reconnectInitialDelay = Duration(seconds: 1);
  static const Duration reconnectMaxDelay = Duration(seconds: 30);

  /// Minimum spacing between full [ConnectionProvider.connect] calls (PWA reconnect storms).
  static const Duration reconnectConnectCooldown = Duration(seconds: 2);
}
