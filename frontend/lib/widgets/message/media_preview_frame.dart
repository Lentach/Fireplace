import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fast_thumbhash/fast_thumbhash.dart';
import 'package:flutter/material.dart';

class MediaPreviewFrame extends StatelessWidget {
  static const legacyHeight = 220.0;
  static const _maximumWidth = 360.0;
  static const _maximumHeight = 400.0;
  static const _minimumRatio = 0.5;
  static const _maximumRatio = 3.0;

  final int? mediaWidth;
  final int? mediaHeight;
  final String? mediaThumbHash;
  final Widget child;

  const MediaPreviewFrame({
    super.key,
    required this.mediaWidth,
    required this.mediaHeight,
    required this.mediaThumbHash,
    required this.child,
  });

  static Size calculateSize({
    required double availableWidth,
    required double viewportHeight,
    required int? mediaWidth,
    required int? mediaHeight,
  }) {
    final width = availableWidth.isFinite
        ? math.min(availableWidth, _maximumWidth)
        : _maximumWidth;
    if (width <= 0 ||
        mediaWidth == null ||
        mediaHeight == null ||
        mediaWidth <= 0 ||
        mediaHeight <= 0) {
      return Size(width, legacyHeight);
    }

    final maximumHeight = math.min(viewportHeight * 0.52, _maximumHeight);
    final ratio = (mediaWidth / mediaHeight)
        .clamp(_minimumRatio, _maximumRatio)
        .toDouble();

    var frameWidth = width;
    var frameHeight = frameWidth / ratio;
    if (frameHeight > maximumHeight) {
      frameHeight = maximumHeight;
      frameWidth = frameHeight * ratio;
    }

    return Size(frameWidth, frameHeight);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = calculateSize(
          availableWidth: constraints.maxWidth,
          viewportHeight: MediaQuery.sizeOf(context).height,
          mediaWidth: mediaWidth,
          mediaHeight: mediaHeight,
        );
        return SizedBox(
          key: const ValueKey('media_preview_frame'),
          width: size.width,
          height: size.height,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ThumbHashBackground(value: mediaThumbHash),
                child,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Paints a ThumbHash placeholder from RAW RGBA pixels.
///
/// Deliberately NOT `ThumbHash.toImage()`: that provider serialises the hash
/// through the package's own hand-rolled PNG encoder, and Flutter web's
/// browser `ImageDecoder` REJECTS the result ("EncodingError: Failed to decode
/// frame at index 0"). Every placeholder on web silently failed — invisible
/// behind a loaded photo, but a video poster has no foreground image, so the
/// bubble rendered blank.
///
/// `ui.decodeImageFromPixels` takes the decoded pixels straight from
/// [ThumbHash.toRGBA], so no image codec is involved on any platform.
class _ThumbHashBackground extends StatefulWidget {
  final String? value;

  const _ThumbHashBackground({required this.value});

  @override
  State<_ThumbHashBackground> createState() => _ThumbHashBackgroundState();
}

class _ThumbHashBackgroundState extends State<_ThumbHashBackground> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_ThumbHashBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _image?.dispose();
      _image = null;
      _decode();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _decode() {
    final value = widget.value;
    if (value == null || value.isEmpty) return;
    final ThumbHashImage decoded;
    try {
      decoded = ThumbHash.fromBase64(value).toRGBA();
    } catch (_) {
      // A malformed hash is a cosmetic loss, never a broken bubble.
      return;
    }
    ui.decodeImageFromPixels(
      decoded.rgba,
      decoded.width,
      decoded.height,
      ui.PixelFormat.rgba8888,
      (image) {
        // The callback can land after the frame scrolled away.
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() => _image = image);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.expand();
    return RawImage(image: image, fit: BoxFit.cover);
  }
}
