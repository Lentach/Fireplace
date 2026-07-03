import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/encryption_provider.dart';
import '../../providers/messaging_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/reply_preview_helper.dart';
import '../../utils/message_edit_eligibility.dart';
import '../../utils/jumbo_emoji.dart';
import '../message_swipe_wrapper.dart';
import '../dialogs/message_delete_dialog.dart';
import '../top_snackbar.dart';
import 'message_context_menu_overlay.dart';
import 'message_context_menu_bubble_highlight.dart';
import 'context_menu_bubble_anchor.dart';
import 'message_bubble_inline_time.dart';
import 'message_content_factory.dart';
import 'voice_message_content.dart';
import 'message_metadata_row.dart';
import 'reaction_chips_row.dart';

export 'reaction_chips_row.dart' show ReactionChipsRow;

class ChatMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  String _displayContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (message.content == '[Decryption failed]') return l10n.decryptionFailed;
    if (message.content == '[Encryption not initialized]') {
      return l10n.encryptionNotInitialized;
    }
    if (message.content.isNotEmpty) return message.content;
    return l10n.unsupportedMessageType;
  }

  Widget _buildReplyQuote(
    BuildContext context,
    ReplyToPreview replyTo,
    bool isDark,
    Color textColor,
    Color borderColor,
  ) {
    final l10n = AppLocalizations.of(context);
    final mutedColor = isDark
        ? RpgTheme.timeColorDark
        : RpgTheme.textSecondaryLight;
    return Container(
      padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6, right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: borderColor, width: 3)),
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            replyTo.senderUsername.isNotEmpty
                ? replyTo.senderUsername
                : l10n.unknown,
            style: RpgTheme.bodyFont(
              fontSize: 12,
              color: borderColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _replyDisplayContent(context, replyTo),
            style: RpgTheme.bodyFont(fontSize: 12, color: mutedColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _replyDisplayContent(BuildContext context, ReplyToPreview replyTo) {
    final l10n = AppLocalizations.of(context);
    final encryption = context.read<EncryptionProvider>();
    final messaging = context.read<MessagingProvider>();
    return replyDisplayContentForQuote(
      l10n,
      replyTo,
      encryption: encryption,
      conversationId: message.conversationId,
      createdAt: message.createdAt,
      messagesForLookup: messaging.messages,
    );
  }

  Widget? _buildRetryButton(BuildContext context) {
    if (!isMine || message.deliveryStatus != MessageDeliveryStatus.failed) {
      return null;
    }
    return TextButton.icon(
      onPressed: () {
        final messaging = Provider.of<MessagingProvider>(
          context,
          listen: false,
        );
        if (message.tempId != null) {
          messaging.retryFailedMessage(message.tempId!);
        }
      },
      icon: const Icon(Icons.refresh, size: 16),
      label: const Text('Retry'),
      style: TextButton.styleFrom(
        foregroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  void _openContextMenu(BuildContext context) {
    final messaging = context.read<MessagingProvider>();
    final auth = context.read<AuthProvider>();
    final renderBox = ContextMenuBubbleAnchor.renderBoxOf(context);
    if (renderBox == null) return;
    final bubbleSize = renderBox.size;
    final themePreference = context.read<SettingsProvider>().themePreference;
    final l10n = AppLocalizations.of(context);
    openMessageContextMenu(
      context: context,
      message: message,
      bubbleRenderBox: renderBox,
      isMine: isMine,
      currentUserId: auth.currentUser?.id,
      bubblePreviewBuilder: (_) => MessageContextMenuBubbleHighlight(
        message: message,
        isMine: isMine,
        maxWidth: bubbleSize.width,
        themePreference: themePreference,
      ),
      onReply: () => messaging.setReplyingTo(message),
      onCopy: !message.hasCopyablePlaintext
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: message.content));
              showTopSnackBar(context, l10n.snackbarMessageCopied);
            },
      onEdit: messageEditEligible(message, isMine: isMine)
          ? () => messaging.beginEditMessage(message)
          : null,
      onPin: () {
        if (message.id > 0) {
          messaging.pinMessage(message.conversationId, message.id);
        }
      },
      onDelete: () {
        showMessageDeleteDialog(
          context: context,
          isMine: isMine,
          messageId: message.id,
          onDeleteForMe: () =>
              messaging.deleteMessage(message.id, forEveryone: false),
          onDeleteForEveryone: () =>
              messaging.deleteMessage(message.id, forEveryone: true),
        );
      },
      onReaction: (emoji, alreadyReacted) {
        if (alreadyReacted) {
          messaging.removeReaction(message.id, emoji);
        } else {
          messaging.addReaction(message.id, emoji);
        }
      },
    );
  }

  Widget _buildContentColumn(
    BuildContext context,
    bool isDark,
    Color textColor,
    Color borderColor, {
    required double contentAreaWidth,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (message.replyTo != null) ...[
          _buildReplyQuote(
            context,
            message.replyTo!,
            isDark,
            textColor,
            borderColor,
          ),
          const SizedBox(height: 8),
        ],
        MessageContentFactory.build(
          context: context,
          message: message,
          isMine: isMine,
          isDark: isDark,
          textColor: textColor,
          contentAreaWidth: contentAreaWidth,
        ),
        Builder(
          builder: (ctx) {
            final retryBtn = _buildRetryButton(ctx);
            if (retryBtn == null) return const SizedBox.shrink();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [const SizedBox(height: 4), retryBtn],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Handle voice messages with dedicated widget
    if (message.messageType == MessageType.voice) {
      return VoiceMessageContent(message: message, isMine: isMine);
    }

    final isDark = RpgTheme.isDark(context);
    final bubbleColor = isMine
        ? FireplaceColors.of(context).mineMsgBg
        : FireplaceColors.of(context).theirsMsgBg;
    final borderColor = isMine
        ? Theme.of(context).colorScheme.primary
        : FireplaceColors.of(context).borderColor;
    final themePreference = context.read<SettingsProvider>().themePreference;
    final textColor = isMine
        ? (themePreference == 'teal'
              ? Colors.white
              : (isDark ? RpgTheme.textColor : RpgTheme.textColorLight))
        : (isDark ? RpgTheme.textColor : RpgTheme.textColorLight);
    final timeColor = RpgTheme.messageBubbleMetaColor(
      context,
      isMine: isMine,
      themePreference: themePreference,
    );

    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    final messaging = context.read<MessagingProvider>();

    return MessageSwipeWrapper(
      isMine: isMine,
      onSwipeReply: () => messaging.setReplyingTo(message),
      onLongPress: () => _openContextMenu(context),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(
            top: message.reactions.isNotEmpty ? 14.0 : 0.0,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              LayoutBuilder(
                builder: (context, layoutConstraints) {
                  final maxBubbleWidth = layoutConstraints.maxWidth * 0.85;
                  final contentAreaWidth = maxBubbleWidth - 32;

                  final isMediaMessage =
                      message.messageType == MessageType.gif ||
                      message.messageType == MessageType.image;
                  final useTextOverlay =
                      message.messageType == MessageType.text &&
                      message.linkPreviewUrl == null;
                  final isEmojiOnlyText =
                      useTextOverlay &&
                      message.replyTo == null &&
                      emojiOnlyCount(message.content) != null;

                  final standardTimeWidget = MessageMetadataRow(
                    message: message,
                    isMine: isMine,
                    timeColor: timeColor,
                  );

                  final mediaTimeOverlay = Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: MessageMetadataRow(
                        message: message,
                        isMine: isMine,
                        timeColor: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  );

                  Widget child;

                  if (isEmojiOnlyText) {
                    return ContextMenuBubbleAnchor(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: isMine ? 48 : 0,
                            right: isMine ? 0 : 48,
                            bottom: kContextMenuAnchorBottomMargin,
                          ),
                          child: Wrap(
                            alignment: isMine
                                ? WrapAlignment.end
                                : WrapAlignment.start,
                            crossAxisAlignment: WrapCrossAlignment.end,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              _buildContentColumn(
                                context,
                                isDark,
                                textColor,
                                borderColor,
                                contentAreaWidth: contentAreaWidth,
                              ),
                              standardTimeWidget,
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  if (isMediaMessage) {
                    child = Stack(
                      children: [
                        _buildContentColumn(
                          context,
                          isDark,
                          textColor,
                          borderColor,
                          contentAreaWidth: contentAreaWidth,
                        ),
                        mediaTimeOverlay,
                      ],
                    );
                  } else if (useTextOverlay) {
                    final displayContent = _displayContent(context);
                    if (messageBubbleUsesInlineTime(
                      message: message,
                      displayContent: displayContent,
                    )) {
                      child = Wrap(
                        alignment: isMine
                            ? WrapAlignment.end
                            : WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          _buildContentColumn(
                            context,
                            isDark,
                            textColor,
                            borderColor,
                            contentAreaWidth: contentAreaWidth,
                          ),
                          standardTimeWidget,
                        ],
                      );
                    } else {
                      child = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isMine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          _buildContentColumn(
                            context,
                            isDark,
                            textColor,
                            borderColor,
                            contentAreaWidth: contentAreaWidth,
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: standardTimeWidget,
                          ),
                        ],
                      );
                    }
                  } else {
                    final displayContent = _displayContent(context);
                    final isShortMessage = messageBubbleUsesInlineTime(
                      message: message,
                      displayContent: displayContent,
                    );

                    if (isShortMessage) {
                      child = Wrap(
                        alignment: isMine
                            ? WrapAlignment.end
                            : WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          _buildContentColumn(
                            context,
                            isDark,
                            textColor,
                            borderColor,
                            contentAreaWidth: contentAreaWidth,
                          ),
                          standardTimeWidget,
                        ],
                      );
                    } else {
                      child = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isMine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          _buildContentColumn(
                            context,
                            isDark,
                            textColor,
                            borderColor,
                            contentAreaWidth: contentAreaWidth,
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: standardTimeWidget,
                          ),
                        ],
                      );
                    }
                  }

                  return ContextMenuBubbleAnchor(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: isMine ? 48 : 0,
                          right: isMine ? 0 : 48,
                          bottom: kContextMenuAnchorBottomMargin,
                        ),
                        child: Container(
                          key: ValueKey('message-bubble-surface-${message.id}'),
                          decoration: BoxDecoration(
                            color: isMediaMessage
                                ? Colors.transparent
                                : bubbleColor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: isMediaMessage
                              ? Clip.hardEdge
                              : Clip.none,
                          padding: isMediaMessage
                              ? (message.replyTo != null
                                    ? const EdgeInsets.only(
                                        top: 8,
                                        left: 12,
                                        right: 12,
                                      )
                                    : EdgeInsets.zero)
                              : const EdgeInsets.fromLTRB(16, 10, 16, 8),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (message.reactions.isNotEmpty)
                Positioned(
                  top: -14,
                  left: isMine ? null : 8,
                  right: isMine ? 8 : null,
                  child: ReactionChipsRow(
                    reactions: message.reactions,
                    currentUserId: currentUserId ?? -1,
                    onTap: (emoji, isMyReaction) {
                      final messaging = context.read<MessagingProvider>();
                      if (isMyReaction) {
                        messaging.removeReaction(message.id, emoji);
                      } else {
                        messaging.addReaction(message.id, emoji);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
