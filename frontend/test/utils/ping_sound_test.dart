import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/ping_sound.dart';

/// The ping-sound facade is a conditional-import split: on web it routes
/// playback through the Web Audio API (no HTML `<audio>` element ⇒ no
/// MediaSession ⇒ no stale iOS media-control card); on native/VM it falls back
/// to just_audio.
///
/// [playPingSound] is exercised by `ping_effect_overlay_test.dart` (the overlay
/// calls it fire-and-forget). It is deliberately NOT called here: under
/// `flutter test` just_audio has no platform channel and throws
/// `MissingPluginException` from internal `init`/`disposeAllPlayers` calls that
/// escape any catch into the test zone. The Web Audio path is DOM-only and
/// invisible to the VM — verified on a real iPhone PWA.
///
/// This test pins the new VM-safe surface: [primePingSound], for which a
/// production call site was added in `ChatDetailScreen.initState`. It must be a
/// safe no-op off web (no AudioPlayer, no platform channel).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('primePingSound() is a safe no-op on the native/VM stub', () {
    expect(primePingSound, returnsNormally);
    // Idempotent — the production call sites may invoke it repeatedly.
    expect(primePingSound, returnsNormally);
  });

  test('VM suite always exercises the native stub, never the web path', () {
    expect(kIsWeb, isFalse);
  });
}
