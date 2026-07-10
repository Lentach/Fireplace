import 'package:just_audio/just_audio.dart';

const String _kPingAsset = 'assets/sounds/ping_alert.wav';

/// Native/VM has no MediaSession concern and no gesture-unlock — no-op.
void primePingSound() {}

/// Native ping playback via `just_audio` — identical to the original
/// `PingEffectOverlay._playPingSound`: load the asset, play once, await
/// completion, then dispose the transient player.
Future<void> playPingSound() async {
  final player = AudioPlayer();
  try {
    await player.setAsset(_kPingAsset);
    await player.play();
    await player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed,
    );
  } catch (_) {
    // Best-effort sound effect — swallow (e.g. no audio platform channel in
    // the VM test environment).
  } finally {
    try {
      await player.dispose();
    } catch (_) {}
  }
}
