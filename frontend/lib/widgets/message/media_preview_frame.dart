import 'dart:math' as math;

import 'package:fast_thumbhash/fast_thumbhash.dart';
import 'package:flutter/material.dart';

class MediaPreviewFrame extends StatelessWidget {
  static const legacyHeight = 220.0;
  static const _maximumWidth = 360.0;
  static const _maximumHeight = 480.0;
  static const _minimumHeight = 96.0;
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
    required double devicePixelRatio,
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

    final maximumHeight = math.min(viewportHeight * 0.65, _maximumHeight);
    final ratio = (mediaWidth / mediaHeight)
        .clamp(_minimumRatio, _maximumRatio)
        .toDouble();
    final sourceWidth = (mediaWidth / devicePixelRatio)
        .clamp(_minimumHeight, width)
        .toDouble();

    var frameWidth = sourceWidth;
    var frameHeight = frameWidth / ratio;
    if (frameHeight > maximumHeight) {
      frameHeight = maximumHeight;
      frameWidth = frameHeight * ratio;
    }

    if (frameHeight < _minimumHeight) {
      final minimumWidth = _minimumHeight * ratio;
      if (minimumWidth <= width) {
        frameWidth = minimumWidth;
        frameHeight = _minimumHeight;
      }
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
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
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

class _ThumbHashBackground extends StatelessWidget {
  final String? value;

  const _ThumbHashBackground({required this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.expand();
    try {
      return Image(
        image: ThumbHash.fromBase64(value!).toImage(),
        fit: BoxFit.contain,
      );
    } catch (_) {
      return const SizedBox.expand();
    }
  }
}
