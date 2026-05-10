import 'dart:async';

import '../providers/conversations_provider.dart';
import '../utils/app_badge_math.dart';
import 'badging_bridge_stub.dart'
    if (dart.library.html) 'badging_bridge_web.dart';

/// Keeps the PWA app icon badge in sync with [ConversationsProvider.unreadCounts].
///
/// Web-only effect ([BadgingBridge.isSupported]); debounces rapid list updates.
class UnreadBadgeSync {
  UnreadBadgeSync(
    this._conversations, {
    BadgingBridge? bridge,
    Duration debounce = const Duration(milliseconds: 200),
  })  : _bridge = bridge ?? createBadgingBridge(),
        _debounce = debounce {
    _conversations.addListener(_onConversationsChanged);
    _scheduleFlush();
  }

  final ConversationsProvider _conversations;
  final BadgingBridge _bridge;
  final Duration _debounce;

  Timer? _debounceTimer;
  /// Last capped value sent to the OS (`null` after clear). Integer badge is required for iOS WebKit.
  int? _lastSentCapped;

  void _onConversationsChanged() {
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _flush);
  }

  Future<void> _flush() async {
    _debounceTimer = null;
    if (!_bridge.isSupported) return;

    final raw = sumUnreadBadgeCounts(_conversations.unreadCounts);
    final capped = capUnreadForBadge(raw);

    if (capped == 0) {
      if (_lastSentCapped != null) {
        _lastSentCapped = null;
        await _bridge.clearBadge();
      }
      return;
    }

    if (_lastSentCapped == capped) return;
    _lastSentCapped = capped;
    await _bridge.setBadgeCount(capped);
  }

  /// Stops listening. Does **not** clear the OS badge — closing the PWA (recents swipe)
  /// must not wipe the icon badge while unread remain; badge clears via [_flush] when
  /// unread hits zero, or [clearPwaAppBadgeOnLogout] on logout.
  Future<void> dispose() async {
    _conversations.removeListener(_onConversationsChanged);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _lastSentCapped = null;
  }
}
