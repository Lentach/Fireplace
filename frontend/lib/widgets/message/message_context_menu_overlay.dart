import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../top_snackbar.dart';
import 'context_menu_bubble_anchor.dart';
import 'message_action_panel.dart';

OverlayEntry? _activeMessageContextMenu;

const _kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

/// Estimated height of [MessageActionPanel] (4 rows × ~46dp); used for overlay layout.
const kMessageActionPanelHeightEstimate = 184.0;

/// Estimated height of the reaction emoji pill row; keep in sync with overlay UI.
const kMessageContextMenuEmojiRowHeight = 44.0;

/// Vertical gap between emoji row, bubble highlight, and action panel.
const kMessageContextMenuOverlayGap = 12.0;

const _kComposerClearance = 88.0;
const _kScrimBlurSigma = 12.0;
const _kElevatedBubbleScale = 1.02;

@visibleForTesting
double bubbleHighlightScaleOverflow(double bubbleHeight) =>
    bubbleHeight * (_kElevatedBubbleScale - 1) / 2;

/// Anchor [RenderBox] includes [kContextMenuAnchorBottomMargin]; layout uses the
/// painted bubble footprint only.
@visibleForTesting
Rect bubbleRectForContextMenuLayout(Rect globalAnchorRect) {
  return Rect.fromLTWH(
    globalAnchorRect.left,
    globalAnchorRect.top,
    globalAnchorRect.width,
    math.max(
      0,
      globalAnchorRect.height - kContextMenuAnchorBottomMargin,
    ),
  );
}

/// Visual top of the scaled highlight replica (global coordinates).
@visibleForTesting
double bubbleHighlightVisualTop({
  required double bubbleHighlightTop,
  required double layoutBubbleHeight,
}) =>
    bubbleHighlightTop -
    bubbleHighlightScaleOverflow(layoutBubbleHeight);

/// Visual bottom of the scaled highlight replica (global coordinates).
@visibleForTesting
double bubbleHighlightVisualBottom({
  required double bubbleHighlightTop,
  required double layoutBubbleHeight,
}) =>
    bubbleHighlightTop +
    layoutBubbleHeight +
    bubbleHighlightScaleOverflow(layoutBubbleHeight);

/// Gap from scaled highlight bottom to action panel top.
@visibleForTesting
double messageContextMenuPanelTop({
  required double bubbleHighlightTop,
  required double layoutBubbleHeight,
}) =>
    bubbleHighlightVisualBottom(
      bubbleHighlightTop: bubbleHighlightTop,
      layoutBubbleHeight: layoutBubbleHeight,
    ) +
    kMessageContextMenuOverlayGap;

typedef _ContextMenuStackLayout = ({
  double emojiTop,
  double panelTop,
  double bubbleHighlightTop,
});

/// Telegram layout around the bubble: emoji row (top) → bubble → panel (bottom).
///
/// All three elements share one anchor rect ([bubbleRect]) with equal vertical
/// gaps. When the message sits near the composer, the whole stack shifts up so
/// the action panel stays fully visible. If there is still not enough room above
/// the bubble for the emoji row, the order becomes emoji → panel → bubble.
///
/// [panelAboveBubble] is a test/diagnostic flag only — production overlay code
/// does not branch on it.
@visibleForTesting
({
  double emojiTop,
  double panelTop,
  double bubbleHighlightTop,
  bool panelAboveBubble,
}) computeMessageContextMenuLayout({
  required Rect bubbleRect,
  required EdgeInsets viewPadding,
  required Size viewSize,
  required double keyboardBottom,
  double composerClearance = _kComposerClearance,
}) {
  const panelHeight = kMessageActionPanelHeightEstimate;
  const emojiHeight = kMessageContextMenuEmojiRowHeight;
  const gap = kMessageContextMenuOverlayGap;
  final minTop = viewPadding.top;
  final maxContentBottom = viewSize.height - keyboardBottom - composerClearance;
  final bubbleHeight = bubbleRect.height;
  final scaleOverflow = bubbleHighlightScaleOverflow(bubbleHeight);

  _ContextMenuStackLayout standardStack(double bubbleTop) {
    final panelTopValue = messageContextMenuPanelTop(
      bubbleHighlightTop: bubbleTop,
      layoutBubbleHeight: bubbleHeight,
    );
    return (
      bubbleHighlightTop: bubbleTop,
      emojiTop: bubbleHighlightVisualTop(
            bubbleHighlightTop: bubbleTop,
            layoutBubbleHeight: bubbleHeight,
          ) -
          emojiHeight -
          gap,
      panelTop: panelTopValue,
    );
  }

  _ContextMenuStackLayout invertedStack(double emojiTopValue) {
    final panelTopValue = emojiTopValue + emojiHeight + gap;
    return (
      emojiTop: emojiTopValue,
      panelTop: panelTopValue,
      bubbleHighlightTop: panelTopValue + panelHeight + gap,
    );
  }

  double bubbleVisualBottom(_ContextMenuStackLayout stack) =>
      stack.bubbleHighlightTop + bubbleHeight + scaleOverflow;

  var stack = standardStack(bubbleRect.top);
  var panelAboveBubble = false;

  final panelBottom = stack.panelTop + panelHeight;
  if (panelBottom > maxContentBottom) {
    stack = standardStack(
      bubbleRect.top - (panelBottom - maxContentBottom),
    );
  }

  if (stack.emojiTop < minTop) {
    panelAboveBubble = true;
    stack = invertedStack(minTop);

    final overflow = bubbleVisualBottom(stack) - maxContentBottom;
    if (overflow > 0) {
      stack = invertedStack(minTop - overflow);
      if (stack.emojiTop < minTop) {
        final bubbleTop = maxContentBottom - bubbleHeight - scaleOverflow;
        final panelTopValue = bubbleTop - gap - panelHeight;
        final emojiTopValue = panelTopValue - gap - emojiHeight;
        stack = (
          emojiTop: emojiTopValue < minTop ? minTop : emojiTopValue,
          panelTop: panelTopValue,
          bubbleHighlightTop: bubbleTop,
        );
      }
    }
  }

  return (
    emojiTop: stack.emojiTop,
    panelTop: stack.panelTop,
    bubbleHighlightTop: stack.bubbleHighlightTop,
    panelAboveBubble: panelAboveBubble,
  );
}

@visibleForTesting
double computeEmojiBarLeft({
  required Rect bubbleRect,
  required EdgeInsets viewPadding,
  required Size viewSize,
  required bool isMine,
  required double emojiBarWidth,
}) {
  final rawLeft =
      isMine ? bubbleRect.right - emojiBarWidth : bubbleRect.left;
  return rawLeft.clamp(
    viewPadding.left,
    viewSize.width - viewPadding.right - emojiBarWidth,
  );
}

@visibleForTesting
double computePanelLeft({
  required Rect bubbleRect,
  required EdgeInsets viewPadding,
  required Size viewSize,
  required bool isMine,
  required double panelWidth,
}) {
  final rawLeft = isMine ? bubbleRect.right - panelWidth : bubbleRect.left;
  return rawLeft.clamp(
    viewPadding.left,
    viewSize.width - viewPadding.right - panelWidth,
  );
}

void _dismissMessageContextMenu() {
  _activeMessageContextMenu?.remove();
  _activeMessageContextMenu = null;
}

void dismissMessageContextMenu() => _dismissMessageContextMenu();

typedef MessageContextMenuBubbleBuilder = Widget Function(BuildContext overlayContext);

void openMessageContextMenu({
  required BuildContext context,
  required MessageModel message,
  required RenderBox bubbleRenderBox,
  required bool isMine,
  required int? currentUserId,
  required VoidCallback onReply,
  required VoidCallback onPin,
  required VoidCallback onDelete,
  required void Function(String emoji, bool alreadyReacted) onReaction,
  MessageContextMenuBubbleBuilder? bubblePreviewBuilder,
}) {
  _dismissMessageContextMenu();
  final overlay = Overlay.of(context);
  final l10n = AppLocalizations.of(context);
  final anchorRect = bubbleRenderBox.localToGlobal(Offset.zero) &
      bubbleRenderBox.size;
  final layoutRect = bubbleRectForContextMenuLayout(anchorRect);
  final viewPadding = MediaQuery.paddingOf(context);
  final viewSize = MediaQuery.sizeOf(context);
  final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
  final canPinOrDeleteForEveryone = message.id > 0;
  final bubblePreview =
      bubblePreviewBuilder?.call(context);

  _activeMessageContextMenu = OverlayEntry(
    builder: (ctx) {
      final layout = computeMessageContextMenuLayout(
        bubbleRect: layoutRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        keyboardBottom: keyboardBottom,
      );
      final bubbleAlign =
          isMine ? Alignment.centerRight : Alignment.centerLeft;

      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: dismissMessageContextMenu,
              behavior: HitTestBehavior.opaque,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _kScrimBlurSigma,
                    sigmaY: _kScrimBlurSigma,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
          if (bubblePreview != null)
            Positioned(
              key: const Key('context-menu-bubble-highlight'),
              left: layoutRect.left,
              top: layout.bubbleHighlightTop,
              width: layoutRect.width,
              child: IgnorePointer(
                child: Transform.scale(
                  scale: _kElevatedBubbleScale,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: layoutRect.width,
                    height: layoutRect.height,
                    child: bubblePreview,
                  ),
                ),
              ),
            ),
          Positioned(
            key: const Key('context-menu-emoji-bar'),
            top: layout.emojiTop,
            left: isMine ? null : layoutRect.left,
            right: isMine ? viewSize.width - layoutRect.right : null,
            child: _ContextMenuReactionEmojiBar(
              message: message,
              currentUserId: currentUserId,
              onReaction: onReaction,
            ),
          ),
          Positioned(
            key: const Key('context-menu-action-panel'),
            top: layout.panelTop,
            left: layoutRect.left,
            width: layoutRect.width,
            child: Align(
              alignment: bubbleAlign,
              child: MessageActionPanel(
                isMine: isMine,
                canPinOrDeleteForEveryone: canPinOrDeleteForEveryone,
                onReply: () {
                  dismissMessageContextMenu();
                  onReply();
                },
                onEdit: () {
                  dismissMessageContextMenu();
                  showTopSnackBar(context, l10n.messageEditComingSoon);
                },
                onPin: () {
                  dismissMessageContextMenu();
                  if (message.id <= 0) {
                    showTopSnackBar(
                      context,
                      l10n.messagePinRequiresSentMessage,
                    );
                  } else {
                    onPin();
                  }
                },
                onDelete: () {
                  dismissMessageContextMenu();
                  onDelete();
                },
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(_activeMessageContextMenu!);
}

class _ContextMenuReactionEmojiBar extends StatelessWidget {
  const _ContextMenuReactionEmojiBar({
    required this.message,
    required this.currentUserId,
    required this.onReaction,
  });

  final MessageModel message;
  final int? currentUserId;
  final void Function(String emoji, bool alreadyReacted) onReaction;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: kMessageContextMenuEmojiRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _kReactionEmojis.map((emoji) {
              final alreadyReacted = currentUserId != null &&
                  (message.reactions[emoji]?.contains(currentUserId) ?? false);
              return GestureDetector(
                onTap: () {
                  onReaction(emoji, alreadyReacted);
                  dismissMessageContextMenu();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: alreadyReacted
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
