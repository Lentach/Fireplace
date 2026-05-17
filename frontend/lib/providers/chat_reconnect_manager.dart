import 'dart:async';

import '../constants/app_constants.dart';

/// Encapsulates WebSocket reconnection state and exponential backoff scheduling.
/// Used by [ConnectionProvider] to reconnect after disconnect (unless intentional or max attempts reached).
class ChatReconnectManager {
  bool intentionalDisconnect = false;
  String? tokenForReconnect;
  int reconnectAttempts = 0;
  Timer? _timer;

  DateTime? _lastReconnectFireAt;

  /// Schedules [onConnect] after [delay] (respects intentional disconnect / missing token).
  void scheduleReconnectAfter(Duration delay, void Function() onConnect) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (intentionalDisconnect || tokenForReconnect == null) return;
      _lastReconnectFireAt = DateTime.now();
      onConnect();
    });
  }

  /// Backoff delay for the current [reconnectAttempts], plus minimum spacing since last fire.
  Duration delayUntilNextReconnect() {
    final exponential = AppConstants.reconnectInitialDelay.inMilliseconds *
        (1 << (reconnectAttempts - 1).clamp(0, 31));
    final capped =
        exponential.clamp(0, AppConstants.reconnectMaxDelay.inMilliseconds);
    var wait = Duration(milliseconds: capped);
    final last = _lastReconnectFireAt;
    if (last != null) {
      final since = DateTime.now().difference(last);
      final minGap = AppConstants.reconnectConnectCooldown - since;
      if (minGap > wait) wait = minGap;
    }
    return wait;
  }

  void scheduleReconnect(void Function() onConnect) {
    reconnectAttempts++;
    scheduleReconnectAfter(delayUntilNextReconnect(), onConnect);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Called when socket disconnects. Returns true if reconnect was scheduled, false otherwise.
  bool onDisconnect(void Function() onConnect, void Function(String) onMaxAttemptsReached) {
    if (intentionalDisconnect || tokenForReconnect == null) return false;
    if (reconnectAttempts >= AppConstants.reconnectMaxAttempts) {
      onMaxAttemptsReached('Connection lost. Please refresh the page.');
      return false;
    }
    scheduleReconnect(onConnect);
    return true;
  }

  void resetAttempts() {
    reconnectAttempts = 0;
  }
}
