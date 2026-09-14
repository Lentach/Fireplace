import 'package:flutter/material.dart';

import 'swipe_down_to_dismiss.dart';

/// The fullscreen stage for a still image or GIF: pinch-zoom, tap to close,
/// and swipe-down-to-dismiss with the same physics as the video viewer
/// (`frontend/docs/composer-media.md`, "Fullscreen swipe-down is animated").
///
/// Owner-requested 2026-09-14: the still viewers only had tap-to-close, so a
/// swipe down did nothing while the same gesture dismissed a video.
///
/// The zoom/drag hand-off is the load-bearing part. `InteractiveViewer` claims
/// the vertical drag whenever panning is enabled, which would starve the
/// ancestor dismiss recognizer — so panning is enabled ONLY while zoomed in,
/// and the dismiss drag is armed only at rest scale. One gesture owner at a
/// time, decided by scale, rather than two recognizers fighting the arena.
class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({required this.image, super.key, this.actions});

  /// The decoded image widget (`Image.memory` / `Image.network`).
  final Widget image;

  /// Optional top-right controls (copy/save). Mounted above the stage so a tap
  /// on them is claimed by their own recognizers, never by tap-to-close.
  final Widget? actions;

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  final TransformationController _transform = TransformationController();

  /// Rest scale within float noise: `InteractiveViewer` can settle a hair off
  /// 1.0 after a pinch-out that snaps back.
  static const _kRestScaleEpsilon = 0.01;

  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed =
        _transform.value.getMaxScaleOnAxis() > 1 + _kRestScaleEpsilon;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return SwipeDownToDismiss(
      onTap: () => Navigator.pop(context),
      canDrag: () => !_zoomed,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 0.5,
              maxScale: 4,
              // See the class doc: panning off at rest scale hands the
              // vertical drag to the dismiss recognizer.
              panEnabled: _zoomed,
              child: widget.image,
            ),
          ),
          if (widget.actions != null)
            Positioned(top: 0, left: 0, right: 0, child: widget.actions!),
        ],
      ),
    );
  }
}
