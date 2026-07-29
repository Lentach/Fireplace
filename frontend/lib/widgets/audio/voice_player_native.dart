// StreamAudioSource/StreamAudioResponse carry an @experimental annotation but
// have been just_audio's documented custom-source API for years; the in-memory
// source below is the only way sealed voice notes can play without writing
// plaintext back to disk. Revisit on any just_audio upgrade.
// ignore_for_file: experimental_member_use
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
      // Sealed voice notes are decrypted to MEMORY and must never touch disk
      // as plaintext, so the file path is not an option for them. just_audio
      // serves a StreamAudioSource through its local proxy — range handling
      // in [_BytesAudioSource] must stay correct or seek silently breaks.
      _player.setAudioSource(_BytesAudioSource(bytes));

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

/// In-memory audio source with proper range semantics: honors both bounds,
/// reports the FULL length as [StreamAudioResponse.sourceLength] (ExoPlayer
/// derives seekability from it), and hands back only the requested window.
class _BytesAudioSource extends StreamAudioSource {
  _BytesAudioSource(this._bytes);

  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = (start ?? 0).clamp(0, _bytes.length);
    final to = (end ?? _bytes.length).clamp(from, _bytes.length);
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(Uint8List.sublistView(_bytes, from, to)),
      // The recorder produces AAC in an MP4 container; ExoPlayer sniffs the
      // real format regardless, this is only the proxy's Content-Type.
      contentType: 'audio/mp4',
    );
  }
}
