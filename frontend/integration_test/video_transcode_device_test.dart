import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fireplace/utils/video_probe_stub.dart'
    if (dart.library.html) 'package:fireplace/utils/video_probe_web.dart'
    if (dart.library.io) 'package:fireplace/utils/video_probe_io.dart'
    as video_probe;
import 'package:fireplace/utils/video_transcode_stub.dart'
    if (dart.library.io) 'package:fireplace/utils/video_transcode_io.dart'
    as video_transcode;

/// ON-DEVICE acceptance for the move-4 transcode: the REAL MediaCodec pipeline
/// (light_compressor_v2) fed a REAL container, output proven decodable.
///
///   cd frontend && flutter test integration_test -d `emulator id`
///
/// The host `flutter test` binding has no codec channel, so on the VM
/// `transcodeVideoToFit` only ever exercises its null-fallback path — this is
/// the only check that the native branch produces bytes at all.
///
/// Fixture: same convention (and same file) as `video_probe_device_test.dart`:
///
///   adb push docs/design/cosmic/cosmic-dimming.mp4 /data/local/tmp/clip.mp4
///   adb shell chmod 644 /data/local/tmp/clip.mp4
///
/// `/data/local/tmp` specifically — `/sdcard/Download` is scoped-storage
/// blocked and app dirs are destroyed by the post-run uninstall. Absent
/// fixture SKIPS rather than fails.
const _fixturePath = '/data/local/tmp/clip.mp4';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('native video transcode', () {
    late final Uint8List? fixtureBytes;

    setUpAll(() {
      try {
        fixtureBytes = File(_fixturePath).readAsBytesSync();
      } catch (_) {
        fixtureBytes = null;
      }
    });

    testWidgets('platform reports transcode support', (_) async {
      expect(video_transcode.isVideoTranscodeSupported, isTrue);
    });

    testWidgets('produces a decodable, cap-sized output from a real clip', (
      _,
    ) async {
      final bytes = fixtureBytes;
      if (bytes == null) {
        markTestSkipped('fixture missing: push $_fixturePath first');
        return;
      }

      final out = await video_transcode.transcodeVideoToFit(bytes);

      // Wiring proof: channel reached, codec ran, temp files round-tripped.
      expect(out, isNotNull, reason: 'transcode returned null on-device');
      expect(out!.length, greaterThan(0));
      // The production gate re-checks the 20 MB cap after transcoding; this
      // fixture is far below the cap, so the output must be too (the solver
      // clamps to the source bitrate — it never inflates a small clip past
      // its target).
      expect(out.length, lessThanOrEqualTo(20 * 1024 * 1024));

      // Output must be a PLAYABLE container, not just bytes: the same native
      // probe that sizes bubbles must read real geometry and duration back.
      final preview = await video_probe.probeVideoPreview(out);
      expect(preview.width, isNotNull);
      expect(preview.height, isNotNull);
      expect(preview.durationInSeconds, isNotNull);
      expect(preview.durationInSeconds, greaterThan(0));
    });
  });
}
