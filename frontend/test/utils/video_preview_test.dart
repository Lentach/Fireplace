import 'package:fireplace/utils/video_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('videoRotationSwapsAxes', () {
    // Why this matters: video_player reports value.size as the CODED size and
    // value.rotationCorrection separately, and its own aspectRatio getter
    // ignores the rotation. An Android phone recording a portrait clip stores
    // it as 1920x1080 + 90 degrees, so anything trusting `size` verbatim
    // publishes a portrait video as landscape — the receiving bubble would
    // then be confidently the wrong shape rather than merely un-shaped.
    test('quarter turns swap the axes', () {
      expect(videoRotationSwapsAxes(90), isTrue);
      expect(videoRotationSwapsAxes(270), isTrue);
    });

    test('upright and half turns do not', () {
      expect(videoRotationSwapsAxes(0), isFalse);
      expect(videoRotationSwapsAxes(180), isFalse);
    });

    test('normalizes out-of-range and negative rotations', () {
      // Containers are not obliged to report 0..359, and a negative modulo in
      // Dart would otherwise leak through as "no swap".
      expect(videoRotationSwapsAxes(450), isTrue); // 450 % 360 == 90
      expect(videoRotationSwapsAxes(-90), isTrue); // == 270
      expect(videoRotationSwapsAxes(-270), isTrue); // == 90
      expect(videoRotationSwapsAxes(360), isFalse);
      expect(videoRotationSwapsAxes(-180), isFalse);
    });

    test('a rotated portrait recording resolves to portrait geometry', () {
      // The exact shape of the Android defect, expressed as the probe does it.
      const codedWidth = 1920;
      const codedHeight = 1080;
      final swap = videoRotationSwapsAxes(90);
      final width = swap ? codedHeight : codedWidth;
      final height = swap ? codedWidth : codedHeight;

      expect(width, 1080);
      expect(height, 1920);
      expect(height, greaterThan(width));
    });
  });

  group('VideoPreview', () {
    test('hasGeometry requires both axes to be positive', () {
      expect(const VideoPreview(width: 360, height: 480).hasGeometry, isTrue);
      expect(const VideoPreview(width: 360).hasGeometry, isFalse);
      expect(const VideoPreview(height: 480).hasGeometry, isFalse);
      expect(const VideoPreview(width: 0, height: 480).hasGeometry, isFalse);
      expect(VideoPreview.unknown.hasGeometry, isFalse);
    });

    test('durationInSeconds rounds and rejects non-positive or non-finite', () {
      expect(const VideoPreview(durationSeconds: 19.4).durationInSeconds, 19);
      expect(const VideoPreview(durationSeconds: 19.6).durationInSeconds, 20);
      expect(const VideoPreview(durationSeconds: 0).durationInSeconds, isNull);
      expect(const VideoPreview(durationSeconds: -3).durationInSeconds, isNull);
      expect(
        const VideoPreview(durationSeconds: double.infinity).durationInSeconds,
        isNull,
      );
      expect(
        const VideoPreview(durationSeconds: double.nan).durationInSeconds,
        isNull,
      );
      expect(VideoPreview.unknown.durationInSeconds, isNull);
    });
  });
}
