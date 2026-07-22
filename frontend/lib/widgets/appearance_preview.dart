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

  const AppearancePreview({
    super.key,
    required this.themeData,
    required this.background,
    this.width = 96,
    this.height = 58,
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
                border: Border.all(color: colors.convItemBorder),
              ),
              child: background == ChatBackgroundLayer.glyphs
                  ? FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: width * 2,
                        height: height * 2,
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
                left: 8,
                top: 9,
                child: _PreviewBubble(
                  color: colors.theirsMsgBg,
                  width: bubbleWidth,
                ),
              ),
              Positioned(
                right: 8,
                top: 25,
                child: _PreviewBubble(
                  color: colors.mineMsgBg,
                  width: bubbleWidth * 0.86,
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: Container(
                  height: 7,
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
      height: 11,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
