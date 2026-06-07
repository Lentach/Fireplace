import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/voice_audio_coordinator.dart';

class _FakePlayback implements ManagedAudioPlayback {
  int pauseCount = 0;
  @override
  void pauseForCoordinator() => pauseCount++;
}

void main() {
  final c = VoiceAudioCoordinator.instance;

  setUp(c.resetForTest);

  test('starting a second player pauses the first', () {
    final a = _FakePlayback();
    final b = _FakePlayback();
    c.onStartedPlaying(a);
    c.onStartedPlaying(b);
    expect(a.pauseCount, 1);
    expect(b.pauseCount, 0);
  });

  test('re-registering the same player is idempotent (no self-pause)', () {
    final a = _FakePlayback();
    c.onStartedPlaying(a);
    c.onStartedPlaying(a);
    expect(a.pauseCount, 0);
  });

  test('pauseActive pauses the active player and clears it', () {
    final a = _FakePlayback();
    c.onStartedPlaying(a);
    c.pauseActive();
    expect(a.pauseCount, 1);
    c.pauseActive(); // nothing active now
    expect(a.pauseCount, 1);
  });

  test('onStoppedPlaying only clears when it matches the active player', () {
    final a = _FakePlayback();
    final b = _FakePlayback();
    c.onStartedPlaying(a);
    c.onStoppedPlaying(b); // not active → no-op
    c.pauseActive();
    expect(a.pauseCount, 1); // a was still active

    c.onStartedPlaying(a);
    c.onStoppedPlaying(a); // active → cleared
    c.pauseActive();
    expect(a.pauseCount, 1); // not paused again
  });
}
