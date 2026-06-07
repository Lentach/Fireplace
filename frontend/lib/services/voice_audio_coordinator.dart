import 'package:flutter/foundation.dart' show visibleForTesting;

/// A voice player the coordinator can pause. Implemented by the playback State.
abstract class ManagedAudioPlayback {
  void pauseForCoordinator();
}

/// Ensures only one voice message plays at a time, and lets recording / leaving
/// the chat pause the active one. Pure Dart, no Flutter/provider deps.
class VoiceAudioCoordinator {
  static final VoiceAudioCoordinator instance = VoiceAudioCoordinator._();
  VoiceAudioCoordinator._();

  ManagedAudioPlayback? _active;

  /// A player started playing → pause the previously-active one.
  void onStartedPlaying(ManagedAudioPlayback p) {
    if (_active != null && !identical(_active, p)) _active!.pauseForCoordinator();
    _active = p;
  }

  /// A player stopped / completed / disposed → clear if it was active.
  void onStoppedPlaying(ManagedAudioPlayback p) {
    if (identical(_active, p)) _active = null;
  }

  /// Recording start or leaving the chat → pause whatever is active.
  void pauseActive() {
    _active?.pauseForCoordinator();
    _active = null;
  }

  /// Test seam — the shared singleton must not leak `_active` across tests.
  @visibleForTesting
  void resetForTest() => _active = null;
}
