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
  /// Whether we already applied the generic OS badge for the current non-zero unread sum.
  bool _indicatorShown = false;

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

    if (raw <= 0) {
      if (_indicatorShown) {
        _indicatorShown = false;
        await _bridge.clearBadge();
      }
      return;
    }

    if (_indicatorShown) return;
    _indicatorShown = true;
    await _bridge.setBadgeIndicator();
  }

  /// Stops listening and clears the badge (e.g. when leaving [MainShell]).
  Future<void> dispose() async {
    _conversations.removeListener(_onConversationsChanged);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _indicatorShown = false;
    await _bridge.clearBadge();
  }
}
