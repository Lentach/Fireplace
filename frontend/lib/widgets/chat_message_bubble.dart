import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/link_preview_service.dart';
import 'message_swipe_wrapper.dart';
import 'voice_message_bubble.dart';

class ChatMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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

  /// E2E: never show plaintext in reply — use placeholder for encrypted.
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
      case MessageType.drawing:
        return l10n.image;
      case MessageType.ping:
        return l10n.ping;
      default:
        return '';
    }
  }

  String _displayContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (message.content == '[Decryption failed]') return l10n.decryptionFailed;
    if (message.content == '[Encryption not initialized]') return l10n.encryptionNotInitialized;
    if (message.content.isNotEmpty) return message.content;
    return l10n.unsupportedMessageType;
  }

  /// Short = time/timer on the right (compact). Long = time/timer below (full-width text).
  bool _isShortMessage(String displayContent) {
    if (message.replyTo != null || message.linkPreviewUrl != null) return false;
    switch (message.messageType) {
      case MessageType.text:
        return displayContent.length <= 25 && !displayContent.contains('\n');
      case MessageType.ping:
        return true;
      case MessageType.image:
      case MessageType.drawing:
        return true;
      default:
        return false;
    }
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
        if (message.messageType == MessageType.text)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentAreaWidth),
            child: _buildTextWithLinks(context, _displayContent(context), textColor, textAlignRight: isMine),
          )
        else if (message.messageType == MessageType.ping)
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Icon(Icons.campaign, size: 18, color: textColor),
              const SizedBox(width: 6),
              Text(
                'PING!',
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          )
        else if ((message.messageType == MessageType.image ||
                 message.messageType == MessageType.drawing) &&
                 message.mediaUrl != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                message.mediaUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      AppLocalizations.of(context).imageFailedToLoad,
                      style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
                    ),
                  );
                },
              ),
            ),
          )
        else
          Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              _displayContent(context),
              style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
              textAlign: isMine ? TextAlign.right : TextAlign.left,
            ),
          ),
        if (message.linkPreviewUrl != null)
          Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: _buildLinkPreviewCard(context, isDark, textColor),
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

  /// One check = delivered (reached recipient device). Two checks = read (recipient opened/read).
  /// Uses light colors so the icon is visible on the dark "mine" bubble (mineMsgBg / mineMsgBgLight).
  Widget _buildDeliveryIcon() {
    if (!isMine) return const SizedBox.shrink();

    if (message.deliveryStatus == MessageDeliveryStatus.failed) {
      return const Icon(Icons.error, size: 12, color: Colors.red);
    }

    IconData icon;
    switch (message.deliveryStatus) {
      case MessageDeliveryStatus.sending:
        icon = Icons.access_time;
        break;
      case MessageDeliveryStatus.sent:
      case MessageDeliveryStatus.delivered:
        icon = Icons.check;
        break;
      case MessageDeliveryStatus.read:
        icon = Icons.done_all;
        break;
      case MessageDeliveryStatus.failed:
        icon = Icons.error;
        break;
    }

    const Color sendingSentColor = Color(0xFFE0E0E0); // light, visible on dark bubble
    const Color readColor = Color(0xFF64B5F6); // light blue for read receipts

    final color = message.deliveryStatus == MessageDeliveryStatus.read ? readColor : sendingSentColor;
    return Icon(icon, size: 12, color: color);
  }

  /// Time + delivery icon + disappearing timer row (Telegram style: right side of bubble).
  Widget _buildTimeDeliveryTimerRow(BuildContext context, Color timeColor) {
    return ValueListenableBuilder<int>(
      valueListenable: context.read<ChatProvider>().countdownTickNotifier,
      builder: (_, __, ___) {
        final timerText = _getTimerText();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatTime(message.createdAt),
              style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
            ),
            const SizedBox(width: 4),
            _buildDeliveryIcon(),
            if (timerText != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.timer_outlined, size: 10, color: timeColor),
              const SizedBox(width: 2),
              Text(
                timerText,
                style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
              ),
            ],
          ],
        );
      },
    );
  }

  void _showReactionOptions(BuildContext context) {
    final chat = context.read<ChatProvider>();
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
                    chat.removeReaction(message.id, emoji);
                  } else {
                    chat.addReaction(message.id, emoji);
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

  Widget? _buildRetryButton(BuildContext context) {
    if (!isMine || message.deliveryStatus != MessageDeliveryStatus.failed) {
      return null;
    }

    return TextButton.icon(
      onPressed: () {
        final chat = Provider.of<ChatProvider>(context, listen: false);
        if (message.tempId != null) {
          chat.retryFailedMessage(message.tempId!);
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

  String? _getTimerText() {
    if (message.expiresAt == null) return null;

    final now = DateTime.now();
    final remaining = message.expiresAt!.difference(now);

    // Expired messages are removed by ChatProvider.removeExpiredMessages()
    if (remaining.isNegative) return null;

    if (remaining.inHours > 0) {
      return '${remaining.inHours}h';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m';
    } else {
      return '${remaining.inSeconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle voice messages with dedicated widget
    if (message.messageType == MessageType.voice) {
      return VoiceMessageBubble(
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
    final chat = context.read<ChatProvider>();

    return MessageSwipeWrapper(
      isMine: isMine,
      onSwipeReply: () => chat.setReplyingTo(message),
      onSwipeDelete: () => chat.deleteMessage(message.id, forEveryone: isMine),
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
                    _buildTimeDeliveryTimerRow(context, timeColor),
                  ],
                )
              : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
              alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: _buildTimeDeliveryTimerRow(context, timeColor),
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
              final chat = context.read<ChatProvider>();
              if (isMyReaction) {
                chat.removeReaction(message.id, emoji);
              } else {
                chat.addReaction(message.id, emoji);
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

  Widget _buildTextWithLinks(
    BuildContext context,
    String text,
    Color textColor, {
    bool textAlignRight = false,
  }) {
    final urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);
    final spans = <InlineSpan>[];
    int last = 0;

    for (final match in urlRegex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: text.substring(last, match.start),
          style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
        ));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: RpgTheme.bodyFont(
          fontSize: 14,
          color: Colors.blue.shade300,
        ).copyWith(decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(
        text: text.substring(last),
        style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
      ));
    }

    final textAlign = textAlignRight ? TextAlign.right : TextAlign.left;
    if (spans.isEmpty) {
      return Text(
        text,
        style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
        textAlign: textAlign,
      );
    }
    return RichText(
      textAlign: textAlign,
      text: TextSpan(children: spans),
    );
  }

  Widget _buildLinkPreviewCard(BuildContext context, bool isDark, Color textColor) {
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => launchUrl(
          Uri.parse(message.linkPreviewUrl!),
          mode: LaunchMode.externalApplication,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.linkPreviewImageUrl != null &&
                  LinkPreviewService.isSafeImageUrl(
                    message.linkPreviewImageUrl,
                    message.linkPreviewUrl,
                  ))
                Image.network(
                  message.linkPreviewImageUrl!,
                  width: double.infinity,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, err, st) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.linkPreviewTitle != null)
                      Text(
                        message.linkPreviewTitle!,
                        style: RpgTheme.bodyFont(
                          fontSize: 13,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 2),
                    Text(
                      message.linkPreviewUrl!,
                      style: RpgTheme.bodyFont(
                        fontSize: 11,
                        color: isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReactionChipsRow extends StatelessWidget {
  final Map<String, List<int>> reactions;
  final int currentUserId;
  final void Function(String emoji, bool isMine) onTap;

  const ReactionChipsRow({
    super.key,
    required this.reactions,
    required this.currentUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chips = reactions.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) {
          final isMine = e.value.contains(currentUserId);
          return GestureDetector(
            onTap: () => onTap(e.key, isMine),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isMine
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMine
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
              child: Text('${e.key} ${e.value.length}', style: const TextStyle(fontSize: 12)),
            ),
          );
        }).toList();

    return Wrap(spacing: 4, runSpacing: 2, children: chips);
  }
}
