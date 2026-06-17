import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'voice_player.dart';

/// Native [VoicePlayer]: a thin 1:1 wrapper around just_audio's [AudioPlayer].
///
/// Behaviour is identical to the pre-refactor `PlaybackController` (which used
/// an `AudioPlayer` directly), including the OS media controls just_audio
/// registers — wanted on Android.
class NativeVoicePlayer implements VoicePlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<VoicePlayerState> get stateStream => _player.playerStateStream.map(
        (s) => VoicePlayerState(
          playing: s.processingState == ProcessingState.completed
              ? false
              : s.playing,
          completed: s.processingState == ProcessingState.completed,
        ),
      );

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Duration? get duration => _player.duration;

  @override
  Future<void> setFilePath(String path) => _player.setFilePath(path);

  @override
  Future<void> setUrl(String url) => _player.setUrl(url);

  @override
  Future<void> setAudioBytes(Uint8List bytes) =>
      throw UnsupportedError('setAudioBytes is web-only');

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> dispose() => _player.dispose();
}

VoicePlayer createVoicePlayer() => NativeVoicePlayer();
