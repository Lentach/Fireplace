import 'package:flutter/material.dart';

import '../models/chat_background_preference.dart';
import '../theme/rpg_theme.dart';
import 'chat_background_pattern.dart';

/// A miniature of the real chat surface. Theme/background selectors use this
/// instead of generic icons so every option shows what it actually changes.
class AppearancePreview extends StatelessWidget {
  final ThemeData themeData;
  final ChatBackgroundLayer background;
  final double width;
  final double height;

  /// Draws the miniature's own rounded outline. True for the Appearance
  /// screen's choice cards, where the border IS the card edge.
  ///
  /// The Settings row sets this false: there the miniature is clipped into a
  /// hex terminal that already paints its own ring, and the radius-12 outline
  /// would cut arcs across the interior. That used to be worked around by
  /// drawing the preview at 92×58 and centre-cropping to the 38px hex — which
  /// hid the border, but also cropped away the strips at `left: 8` and
  /// `right: 8` where BOTH bubbles live, leaving the row showing background
  /// and two slivers. Without the border the miniature can render at the
  /// hex's own size and stay whole.
  final bool showBorder;

  const AppearancePreview({
    super.key,
    required this.themeData,
    required this.background,
    this.width = 96,
    this.height = 58,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    Widget preview = Theme(
      data: themeData,
      child: Builder(
        builder: (context) {
          final colors = FireplaceColors.of(context);
          return RepaintBoundary(
            child: Container(
              width: width,
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: showBorder
                    ? Border.all(color: colors.convItemBorder)
                    : null,
              ),
              child: background == ChatBackgroundLayer.glyphs
                  ? FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: width * _kGlyphsSceneUpscale,
                        height: height * _kGlyphsSceneUpscale,
                        child: _AppearancePreviewScene(
                          colors: colors,
                          background: background,
                        ),
                      ),
                    )
                  : _AppearancePreviewScene(
                      colors: colors,
                      background: background,
                    ),
            ),
          );
        },
      ),
    );

    if (media != null) {
      preview = MediaQuery(
        data: media.copyWith(disableAnimations: true),
        child: preview,
      );
    }
    return preview;
  }
}

/// The scene's layout, exposed because it is ABSOLUTE, not proportional:
/// only bubble WIDTH scales with the box, so any caller that resizes, crops
/// or overflows the miniature has to reason about where the content actually
/// lands. Two bugs came from callers guessing (owner-reported, 2026-07-25):
/// a centre-crop that removed both bubbles, then a shrink that slid the
/// composer bar over the "mine" bubble.
const double kPreviewSideInset = 8;
const double kPreviewTheirBubbleTop = 9;
const double kPreviewMineBubbleTop = 25;
const double kPreviewBubbleHeight = 11;
const double kPreviewComposerBottom = 6;
const double kPreviewComposerHeight = 7;

/// Bottom of the lower bubble, measured from the top of the box.
const double kPreviewContentBottom =
    kPreviewMineBubbleTop + kPreviewBubbleHeight;

/// The shortest box in which the composer bar still clears that bubble.
/// Render the miniature any shorter and the bar paints over it.
const double kPreviewMinHeight =
    kPreviewContentBottom + kPreviewComposerBottom + kPreviewComposerHeight;

/// The `glyphs` background lays the scene out this many times over and then
/// `FittedBox`es it back down to the box — which also halves every ABSOLUTE
/// offset in [_AppearancePreviewScene]. Callers that do their own layout
/// arithmetic on the `kPreview*` constants must therefore either avoid that
/// layer or fold the scaling in; the Settings hex avoids it.
const double _kGlyphsSceneUpscale = 2;

/// Vertical alignment for an [OverflowBox] holding the miniature inside a
/// SHORTER terminal, chosen so the midpoint of the two BUBBLES lands on the
/// terminal's centre — rather than the midpoint of the whole miniature, which
/// would hang them high and wedge-clip the upper one against a hex taper.
double appearancePreviewAlignY({
  required double previewHeight,
  required double terminalHeight,
}) {
  const contentCentre = (kPreviewTheirBubbleTop + kPreviewContentBottom) / 2;
  // Where the miniature's y=0 must land, in terminal coordinates.
  final originY = terminalHeight / 2 - contentCentre;
  final overflow = (previewHeight - terminalHeight) / 2;
  // OverflowBox positions at originY = -overflow - overflow * alignY.
  return -originY / overflow - 1;
}

class _AppearancePreviewScene extends StatelessWidget {
  final FireplaceColors colors;
  final ChatBackgroundLayer background;

  const _AppearancePreviewScene({
    required this.colors,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return ChatBackgroundPattern(
      backgroundColor: colors.messagesAreaBg,
      layer: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bubbleWidth = constraints.maxWidth * 0.42;
          return Stack(
            children: [
              Positioned(
                left: kPreviewSideInset,
                top: kPreviewTheirBubbleTop,
                child: _PreviewBubble(
                  color: colors.theirsMsgBg,
                  width: bubbleWidth,
                ),
              ),
              Positioned(
                right: kPreviewSideInset,
                top: kPreviewMineBubbleTop,
                child: _PreviewBubble(
                  color: colors.mineMsgBg,
                  width: bubbleWidth * 0.86,
                ),
              ),
              Positioned(
                left: kPreviewSideInset,
                right: kPreviewSideInset,
                bottom: kPreviewComposerBottom,
                child: Container(
                  height: kPreviewComposerHeight,
                  decoration: BoxDecoration(
                    color: colors.inputBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.borderColor),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  final Color color;
  final double width;

  const _PreviewBubble({required this.color, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: kPreviewBubbleHeight,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
