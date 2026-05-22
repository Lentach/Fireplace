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

  /// WebSocket reconnection
  static const int reconnectMaxAttempts = 5;
  static const Duration reconnectInitialDelay = Duration(seconds: 1);
  static const Duration reconnectMaxDelay = Duration(seconds: 30);

  /// Minimum spacing between full [ConnectionProvider.connect] calls (PWA reconnect storms).
  static const Duration reconnectConnectCooldown = Duration(seconds: 2);
}
