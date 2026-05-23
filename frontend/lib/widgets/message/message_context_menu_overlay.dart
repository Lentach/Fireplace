import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../top_snackbar.dart';
import 'message_action_panel.dart';

OverlayEntry? _activeMessageContextMenu;

const _kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

void _dismissMessageContextMenu() {
  _activeMessageContextMenu?.remove();
  _activeMessageContextMenu = null;
}

void dismissMessageContextMenu() => _dismissMessageContextMenu();

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
}) {
  _dismissMessageContextMenu();
  final overlay = Overlay.of(context);
  final l10n = AppLocalizations.of(context);
  final bubbleRect = bubbleRenderBox.localToGlobal(Offset.zero) &
      bubbleRenderBox.size;
  final viewPadding = MediaQuery.paddingOf(context);
  final viewSize = MediaQuery.sizeOf(context);
  final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
  final canPinOrDeleteForEveryone = message.id > 0;

  _activeMessageContextMenu = OverlayEntry(
    builder: (ctx) {
      const emojiRowHeight = 52.0;
      const panelGap = 8.0;
      const composerClearance = 200.0;

      final nearComposer = bubbleRect.bottom >
          viewSize.height - keyboardBottom - composerClearance;

      double emojiTop = bubbleRect.top - emojiRowHeight - panelGap;
      if (emojiTop < viewPadding.top) {
        emojiTop = bubbleRect.bottom + panelGap;
      }

      final panelWidthEstimate = 180.0;
      double panelLeft;
      if (isMine) {
        panelLeft = bubbleRect.left - panelWidthEstimate - panelGap;
        if (panelLeft < viewPadding.left) {
          panelLeft = bubbleRect.right + panelGap;
        }
      } else {
        panelLeft = bubbleRect.right + panelGap;
        if (panelLeft + panelWidthEstimate > viewSize.width - viewPadding.right) {
          panelLeft = bubbleRect.left - panelWidthEstimate - panelGap;
        }
      }
      panelLeft = panelLeft.clamp(
        viewPadding.left,
        viewSize.width - viewPadding.right - panelWidthEstimate,
      );

      double panelTop = nearComposer
          ? bubbleRect.top - 160 - panelGap
          : bubbleRect.top;
      panelTop = panelTop.clamp(
        viewPadding.top,
        viewSize.height - keyboardBottom - 160,
      );

      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: dismissMessageContextMenu,
              child: const ColoredBox(color: Color(0x88000000)),
            ),
          ),
          Positioned(
            left: bubbleRect.left.clamp(viewPadding.left, viewSize.width - viewPadding.right - bubbleRect.width),
            top: emojiTop,
            width: bubbleRect.width.clamp(0, viewSize.width - viewPadding.left - viewPadding.right),
            height: emojiRowHeight,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(24),
              color: Theme.of(ctx).colorScheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _kReactionEmojis.map((emoji) {
                  final alreadyReacted = currentUserId != null &&
                      (message.reactions[emoji]?.contains(currentUserId) ?? false);
                  return GestureDetector(
                    onTap: () {
                      onReaction(emoji, alreadyReacted);
                      dismissMessageContextMenu();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: alreadyReacted
                            ? Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.15)
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
          Positioned(
            left: panelLeft,
            top: panelTop,
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
                  showTopSnackBar(context, l10n.messagePinRequiresSentMessage);
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
        ],
      );
    },
  );
  overlay.insert(_activeMessageContextMenu!);
}
