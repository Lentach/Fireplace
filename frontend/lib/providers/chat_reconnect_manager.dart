import 'dart:async';

import '../constants/app_constants.dart';

/// Encapsulates WebSocket reconnection state and exponential backoff scheduling.
/// Used by [ChatProvider] to reconnect after disconnect (unless intentional or max attempts reached).
class ChatReconnectManager {
  bool intentionalDisconnect = false;
  String? tokenForReconnect;
  int reconnectAttempts = 0;
  Timer? _timer;

  /// Schedules a reconnect after exponential backoff. Calls [onConnect] when timer fires.
  void scheduleReconnect(void Function() onConnect) {
    reconnectAttempts++;
    final delay = _reconnectDelay;
    _timer = Timer(delay, () {
      if (intentionalDisconnect || tokenForReconnect == null) return;
      onConnect();
    });
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

  Duration get _reconnectDelay {
    final exponential = AppConstants.reconnectInitialDelay.inMilliseconds * (1 << (reconnectAttempts - 1));
    final capped = exponential.clamp(0, AppConstants.reconnectMaxDelay.inMilliseconds);
    return Duration(milliseconds: capped);
  }
}
