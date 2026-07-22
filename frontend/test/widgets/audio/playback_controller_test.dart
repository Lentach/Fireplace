import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/services/voice_audio_coordinator.dart';
import 'package:fireplace/widgets/audio/playback_controller.dart';
import 'package:fireplace/widgets/audio/voice_player.dart';

/// In-memory [VoicePlayer] so the controller's play/pause/seek/speed wiring can
/// be tested without just_audio or the Web Audio DOM. Reports a known duration
/// so a play tap skips the network/decrypt load path.
class FakeVoicePlayer implements VoicePlayer {
  FakeVoicePlayer({Duration? duration}) : _duration = duration;

  final _state = StreamController<VoicePlayerState>.broadcast();
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration?>.broadcast();
  final Duration? _duration;

  final List<String> calls = <String>[];
  final List<double> speedCalls = <double>[];
  Duration? lastSeek;

  void emitPlaying(bool playing) =>
      _state.add(VoicePlayerState(playing: playing, completed: false));

  void emitCompleted() =>
      _state.add(VoicePlayerState(playing: false, completed: true));

  @override
  Stream<VoicePlayerState> get stateStream => _state.stream;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration?> get durationStream => _dur.stream;
  @override
  Duration? get duration => _duration;

  @override
  Future<void> setFilePath(String path) async => calls.add('setFilePath');
  @override
  Future<void> setUrl(String url) async => calls.add('setUrl');
  @override
  Future<void> setAudioBytes(Uint8List bytes) async => calls.add('setAudioBytes');
  @override
  Future<void> play() async {
    calls.add('play');
    emitPlaying(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emitPlaying(false);
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    lastSeek = position;
  }

  @override
  Future<void> setSpeed(double speed) async {
    calls.add('setSpeed');
    speedCalls.add(speed);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    _state.close();
    _pos.close();
    _dur.close();
  }
}

MessageModel _voiceMessage() => MessageModel(
      id: 1,
      content: '',
      senderId: 2,
      senderUsername: 'alice',
      conversationId: 7,
      createdAt: DateTime(2026, 1, 1),
      messageType: MessageType.voice,
      mediaUrl: 'https://example.test/media/msgs/x.bin',
      mediaDuration: 10,
    );

Widget _host(FakeVoicePlayer fake, MessageModel msg) {
  return MaterialApp(
    home: Scaffold(
      body: PlaybackController(
        message: msg,
        playerFactory: () => fake,
        builder: (context, isPlaying, isLoading, position, duration, speed,
            togglePlayPause, seekFromWaveform, toggleSpeed) {
          return Column(
            children: [
              Text('playing:$isPlaying', key: const Key('playing')),
              Text('speed:$speed', key: const Key('speed')),
              Text('pos:${position.inMilliseconds}', key: const Key('pos')),
              Text('dur:${duration.inMilliseconds}', key: const Key('dur')),
              TextButton(onPressed: togglePlayPause, child: const Text('toggle')),
              TextButton(onPressed: toggleSpeed, child: const Text('speedbtn')),
              TextButton(
                  onPressed: () => seekFromWaveform(50, 100),
                  child: const Text('seek')),
            ],
          );
        },
      ),
    ),
  );
}

void main() {
  setUp(() => VoiceAudioCoordinator.instance.resetForTest());
  tearDown(() => VoiceAudioCoordinator.instance.resetForTest());

  testWidgets('play tap calls player.play and reflects isPlaying',
      (tester) async {
    final fake = FakeVoicePlayer(duration: const Duration(seconds: 10));
    await tester.pumpWidget(_host(fake, _voiceMessage()));

    await tester.tap(find.text('toggle'));
    await tester.pump();

    expect(fake.calls, contains('play'));
    expect(find.text('playing:true'), findsOneWidget);
  });

  testWidgets('second tap pauses', (tester) async {
    final fake = FakeVoicePlayer(duration: const Duration(seconds: 10));
    await tester.pumpWidget(_host(fake, _voiceMessage()));

    await tester.tap(find.text('toggle'));
    await tester.pump();
    await tester.tap(find.text('toggle'));
    await tester.pump();

    expect(fake.calls, containsAllInOrder(['play', 'pause']));
    expect(find.text('playing:false'), findsOneWidget);
  });

  testWidgets('speed toggle cycles 1x -> 1.5x -> 2x -> 1x', (tester) async {
    final fake = FakeVoicePlayer(duration: const Duration(seconds: 10));
    await tester.pumpWidget(_host(fake, _voiceMessage()));

    await tester.tap(find.text('speedbtn'));
    await tester.pump();
    await tester.tap(find.text('speedbtn'));
    await tester.pump();
    await tester.tap(find.text('speedbtn'));
    await tester.pump();

    expect(fake.speedCalls, [1.5, 2.0, 1.0]);
    expect(find.text('speed:1.0'), findsOneWidget);
  });

  testWidgets('waveform seek maps tap fraction to duration', (tester) async {
    final fake = FakeVoicePlayer(duration: const Duration(seconds: 10));
    await tester.pumpWidget(_host(fake, _voiceMessage()));

    await tester.tap(find.text('seek'));
    await tester.pump();

    // localX/width = 50/100 = 0.5 of a 10s clip = 5s.
    expect(fake.lastSeek, const Duration(seconds: 5));
  });

  testWidgets('coordinator pauses a previously-playing controller',
      (tester) async {
    final fake1 = FakeVoicePlayer(duration: const Duration(seconds: 10));
    final fake2 = FakeVoicePlayer(duration: const Duration(seconds: 10));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(height: 100, child: _PlaybackHarness(fake1, 'a')),
              SizedBox(height: 100, child: _PlaybackHarness(fake2, 'b')),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('toggle-a'));
    await tester.pump();
    await tester.tap(find.text('toggle-b'));
    await tester.pump();

    // Starting b must pause a via the coordinator.
    expect(fake1.calls, contains('pause'));
  });

  testWidgets('completion resets isPlaying and rewinds to zero',
      (tester) async {
    final fake = FakeVoicePlayer(duration: const Duration(seconds: 10));
    await tester.pumpWidget(_host(fake, _voiceMessage()));

    await tester.tap(find.text('toggle'));
    await tester.pump();
    expect(find.text('playing:true'), findsOneWidget);

    fake.emitCompleted();
    // First pump processes the state event; a second lets the post-frame
    // callback run stop()+seek(zero).
    await tester.pump();
    await tester.pump();

    expect(find.text('playing:false'), findsOneWidget);
    expect(fake.calls, contains('stop'));
    expect(fake.lastSeek, Duration.zero);
  });
}

class _PlaybackHarness extends StatelessWidget {
  const _PlaybackHarness(this.fake, this.tag);
  final FakeVoicePlayer fake;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return PlaybackController(
      message: _voiceMessage(),
      playerFactory: () => fake,
      builder: (context, isPlaying, isLoading, position, duration, speed,
          togglePlayPause, seekFromWaveform, toggleSpeed) {
        return TextButton(onPressed: togglePlayPause, child: Text('toggle-$tag'));
      },
    );
  }
}
