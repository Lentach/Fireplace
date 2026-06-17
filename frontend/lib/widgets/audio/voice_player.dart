import 'dart:typed_data';

import 'voice_player_native.dart'
    if (dart.library.html) 'voice_player_web.dart' as impl;

/// Immutable snapshot of playback state emitted on [VoicePlayer.stateStream].
class VoicePlayerState {
  final bool playing;
  final bool completed;
  const VoicePlayerState({required this.playing, required this.completed});
}

/// Minimal audio-playback contract the voice bubble needs, decoupled from
/// just_audio.
///
/// - **Native** (`voice_player_native.dart`): thin wrapper around just_audio —
///   behaviour identical to before, and the OS media controls it registers are
///   wanted on Android.
/// - **Web** (`voice_player_web.dart`): plays through the Web Audio API
///   (`AudioContext` + `AudioBufferSourceNode`), which registers **no
///   MediaSession** — so iOS Safari shows no media-control card for voice
///   playback (the same reason the ping moved to Web Audio).
///
/// Each platform supports only its own load entry point; calling the other is
/// an [UnsupportedError]. [PlaybackController] already branches on `kIsWeb`, so
/// it always calls the supported one.
abstract class VoicePlayer {
  /// `{playing, completed}` snapshots. `completed` fires once when playback
  /// reaches the natural end.
  Stream<VoicePlayerState> get stateStream;

  /// Current playback position, emitted while playing.
  Stream<Duration> get positionStream;

  /// Total duration once known (null until loaded/decoded).
  Stream<Duration?> get durationStream;

  /// Total duration if known, else null. Used to decide load-vs-play on tap.
  Duration? get duration;

  /// Native: load from a local file path.
  Future<void> setFilePath(String path);

  /// Native: load from a remote/blob URL.
  Future<void> setUrl(String url);

  /// Web: load + decode already-decrypted audio bytes.
  Future<void> setAudioBytes(Uint8List bytes);

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

/// The platform player: just_audio on native, Web Audio on web.
VoicePlayer createVoicePlayer() => impl.createVoicePlayer();
