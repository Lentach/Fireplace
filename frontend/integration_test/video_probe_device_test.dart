import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fireplace/utils/video_probe_stub.dart'
    if (dart.library.html) 'package:fireplace/utils/video_probe_web.dart'
    if (dart.library.io) 'package:fireplace/utils/video_probe_io.dart'
    as video_probe;

/// ON-DEVICE acceptance for the native video probe: the REAL platform video
/// plugin opening a REAL container.
///
///   cd frontend && flutter test integration_test -d `emulator id`
///
/// The host `flutter test` binding has no video plugin, so `probeVideoPreview`
/// there only ever exercises its failure path (`VideoPreview.unknown`). This is
/// the only check that the Android branch actually reads geometry — which is
/// what sizes the receiving chat bubble, and the reason a video message stopped
/// rendering in a fixed 220 px letterbox.
///
/// Fixture: push a portrait clip to `/data/local/tmp` before running.
///
///   adb push docs/design/cosmic/cosmic-dimming.mp4 /data/local/tmp/clip.mp4
///   adb shell chmod 644 /data/local/tmp/clip.mp4
///
/// That directory specifically, because the two obvious alternatives do not
/// work: `/sdcard/Download` is blocked by scoped storage (it stats fine and
/// then throws on open), and anything under the app's own dirs is destroyed
/// every run — `flutter test integration_test` UNINSTALLS the package when it
/// finishes. `/data/local/tmp` is `drwxrwx--x`, so a 0644 file inside it is
/// readable by any app, and it survives uninstall.
///
/// Absent or unreadable fixture SKIPS rather than fails — the clip is
/// deliberately not bundled as an asset (half a megabyte of APK for one test).
const _fixturePath = '/data/local/tmp/clip.mp4';

// cosmic-dimming.mp4, read from its tkhd box: 1080x2400, 7.66 s.
const _expectedWidth = 1080;
const _expectedHeight = 2400;
const _expectedDurationSeconds = 7.66;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('native video probe', () {
    late final Uint8List? fixtureBytes;

    setUpAll(() {
      // Read-based, not exists-based: a /sdcard path outside the app sandbox
      // stats fine and then throws on open under scoped storage, which would
      // surface as a confusing failure instead of an honest skip.
      try {
        fixtureBytes = File(_fixturePath).readAsBytesSync();
      } catch (_) {
        fixtureBytes = null;
      }
    });

    testWidgets('reads intrinsic geometry from a real container', (_) async {
      final bytes = fixtureBytes;
      if (bytes == null) {
        markTestSkipped('fixture unreadable: $_fixturePath');
        return;
      }
      final preview = await video_probe.probeVideoPreview(bytes);

      // The whole point: geometry must be present. Null here is the defect —
      // the receiving bubble falls back to MediaPreviewFrame.legacyHeight and
      // a portrait clip renders as a squat letterboxed box.
      expect(preview.hasGeometry, isTrue, reason: 'probe returned no geometry');
      expect(preview.width, _expectedWidth);
      expect(preview.height, _expectedHeight);
      // Portrait must survive as portrait. This is what would break if
      // rotationCorrection were ignored on a rotated phone recording.
      expect(preview.height!, greaterThan(preview.width!));
    });

    testWidgets('reads duration from a real container', (_) async {
      final bytes = fixtureBytes;
      if (bytes == null) {
        markTestSkipped('fixture unreadable: $_fixturePath');
        return;
      }
      final preview = await video_probe.probeVideoPreview(bytes);

      // Before this probe existed the native path always answered null, so the
      // composer could not enforce the duration cap on Android at all.
      expect(preview.durationSeconds, isNotNull);
      expect(preview.durationSeconds!, closeTo(_expectedDurationSeconds, 0.5));
      expect(preview.durationInSeconds, 8);
    });

    testWidgets('answers unknown for bytes that are not a video', (_) async {
      // Best-effort contract: an unopenable container must degrade, never throw
      // and never block a send.
      final preview = await video_probe.probeVideoPreview(
        Uint8List.fromList(List<int>.filled(2048, 0x41)),
      );
      expect(preview.hasGeometry, isFalse);
      expect(preview.durationInSeconds, isNull);
    });
  });
}
