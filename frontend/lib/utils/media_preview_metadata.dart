import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fast_thumbhash/fast_thumbhash.dart';

/// Intrinsic media geometry and an optional compact encrypted loading preview.
class MediaPreviewMetadata {
  static const maxDimension = 32768;
  static const _thumbHashMaxSide = 100;

  final int width;
  final int height;
  final String? thumbHash;

  const MediaPreviewMetadata({
    required this.width,
    required this.height,
    this.thumbHash,
  });

  static Future<MediaPreviewMetadata?> fromEncodedBytes(
    Uint8List encodedBytes,
  ) async {
    ui.Codec? sourceCodec;
    ui.Image? sourceImage;
    try {
      sourceCodec = await ui.instantiateImageCodec(
        encodedBytes,
        allowUpscaling: false,
      );
      sourceImage = (await sourceCodec.getNextFrame()).image;
      final width = sourceImage.width;
      final height = sourceImage.height;
      if (width <= 0 ||
          height <= 0 ||
          width > maxDimension ||
          height > maxDimension) {
        return null;
      }

      final thumbHash = await _createThumbHash(
        encodedBytes,
        width: width,
        height: height,
      );
      return MediaPreviewMetadata(
        width: width,
        height: height,
        thumbHash: thumbHash,
      );
    } finally {
      sourceImage?.dispose();
      sourceCodec?.dispose();
    }
  }

  static Future<String?> _createThumbHash(
    Uint8List encodedBytes, {
    required int width,
    required int height,
  }) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      final scale = math.min(1.0, _thumbHashMaxSide / math.max(width, height));
      final targetWidth = math.max(1, (width * scale).round());
      final targetHeight = math.max(1, (height * scale).round());
      codec = await ui.instantiateImageCodec(
        encodedBytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: false,
      );
      image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return null;
      // Keep this synchronous: fast_thumbhash's async helpers use isolates,
      // which Flutter web does not support.
      return base64Encode(
        rgbaToThumbHash(image.width, image.height, pixels.buffer.asUint8List()),
      );
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}
