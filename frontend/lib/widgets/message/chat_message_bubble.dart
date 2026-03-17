import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/messaging_provider.dart';
import '../../theme/rpg_theme.dart';
import '../message_swipe_wrapper.dart';
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
    if (message.content == '[Encryption not initialized]') return l10n.encryptionNotInitialized;
    if (message.content.isNotEmpty) return message.content;
    return l10n.unsupportedMessageType;
  }

  /// Short = time/timer on the right (compact). Long = time/timer below.
  bool _isShortMessage(String displayContent) {
    if (message.replyTo != null || message.linkPreviewUrl != null) return false;
    switch (message.messageType) {
      case MessageType.text:
        return displayContent.length <= 25 && !displayContent.contains('\n');
      case MessageType.ping:
        return true;
      case MessageType.image:
      case MessageType.file:
        return false;
      default:
        return false;
    }
  }

  Widget _buildReplyQuote(
    BuildContext context,
    ReplyToPreview replyTo,
    bool isDark,
    Color textColor,
    Color borderColor,
  ) {
    final l10n = AppLocalizations.of(context);
    final mutedColor = isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight;
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
            replyTo.senderUsername.isNotEmpty ? replyTo.senderUsername : l10n.unknown,
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
    if (replyTo.content == '[encrypted]') return l10n.encryptedMessage;
    if (replyTo.content.isNotEmpty) return replyTo.content;
    return _replyTypeLabel(context, replyTo.messageType);
  }

  String _replyTypeLabel(BuildContext context, MessageType type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case MessageType.voice:
        return l10n.voiceMessage;
      case MessageType.image:
        return l10n.image;
      case MessageType.ping:
        return l10n.ping;
      case MessageType.gif:
        return l10n.actionTileGif;
      case MessageType.file:
        return l10n.attachmentOptionDocument;
      default:
        return '';
    }
  }

  Widget? _buildRetryButton(BuildContext context) {
    if (!isMine || message.deliveryStatus != MessageDeliveryStatus.failed) {
      return null;
    }
    return TextButton.icon(
      onPressed: () {
        final messaging = Provider.of<MessagingProvider>(context, listen: false);
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

  void _showReactionOptions(BuildContext context) {
    final messaging = context.read<MessagingProvider>();
    final currentUserId = context.read<AuthProvider>().currentUser?.id;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['👍', '❤️', '😂', '😮', '😢', '🔥'].map((emoji) {
              final alreadyReacted = currentUserId != null &&
                  (message.reactions[emoji]?.contains(currentUserId) ?? false);
              return GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  if (alreadyReacted) {
                    messaging.removeReaction(message.id, emoji);
                  } else {
                    messaging.addReaction(message.id, emoji);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: alreadyReacted
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
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
      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (message.replyTo != null) ...[
          _buildReplyQuote(context, message.replyTo!, isDark, textColor, borderColor),
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
              crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                retryBtn,
              ],
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
      return VoiceMessageContent(
        message: message,
        isMine: isMine,
      );
    }

    final isDark = RpgTheme.isDark(context);
    final bubbleColor = isMine
        ? FireplaceColors.of(context).mineMsgBg
        : FireplaceColors.of(context).theirsMsgBg;
    final borderColor = isMine
        ? Theme.of(context).colorScheme.primary
        : FireplaceColors.of(context).borderColor;
    final textColor = isMine
        ? (isDark ? RpgTheme.textColor : Colors.white)
        : (isDark ? RpgTheme.textColor : RpgTheme.textColorLight);
    final timeColor =
        isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight;

    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    final messaging = context.read<MessagingProvider>();

    return MessageSwipeWrapper(
      isMine: isMine,
      onSwipeReply: () => messaging.setReplyingTo(message),
      onSwipeDelete: () => messaging.deleteMessage(message.id, forEveryone: isMine),
      onLongPress: () => _showReactionOptions(context),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(top: message.reactions.isNotEmpty ? 14.0 : 0.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              LayoutBuilder(
                builder: (context, layoutConstraints) {
                  final maxBubbleWidth = layoutConstraints.maxWidth * 0.85;
                  final contentAreaWidth = maxBubbleWidth - 32;
                  const timeRowWidth = 88.0;
                  final maxContentWidthInline = contentAreaWidth - 6 - timeRowWidth;

                  final displayContent = _displayContent(context);
                  final isShortMessage = _isShortMessage(displayContent);

                  return ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                    child: Container(
                      margin: EdgeInsets.only(
                        left: isMine ? 48 : 0,
                        right: isMine ? 0 : 48,
                        bottom: 10,
                      ),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: isShortMessage
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: maxContentWidthInline),
                                    child: _buildContentColumn(
                                      context,
                                      isDark,
                                      textColor,
                                      borderColor,
                                      contentAreaWidth: maxContentWidthInline,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                MessageMetadataRow(
                                  message: message,
                                  isMine: isMine,
                                  timeColor: timeColor,
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment:
                                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                                  alignment:
                                      isMine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: MessageMetadataRow(
                                    message: message,
                                    isMine: isMine,
                                    timeColor: timeColor,
                                  ),
                                ),
                              ],
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
