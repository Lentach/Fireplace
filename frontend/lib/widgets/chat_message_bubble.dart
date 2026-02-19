import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/rpg_theme.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
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
            replyTo.senderUsername.isNotEmpty ? replyTo.senderUsername : 'Unknown',
            style: RpgTheme.bodyFont(
              fontSize: 12,
              color: borderColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            replyTo.content.isNotEmpty ? replyTo.content : _replyTypeLabel(replyTo.messageType),
            style: RpgTheme.bodyFont(fontSize: 12, color: mutedColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _replyTypeLabel(MessageType type) {
    switch (type) {
      case MessageType.voice:
        return 'Voice message';
      case MessageType.image:
      case MessageType.drawing:
        return 'Image';
      case MessageType.ping:
        return 'Ping';
      default:
        return '';
    }
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
                        ? RpgTheme.primaryColor(context).withValues(alpha: 0.15)
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
          chat.retryVoiceMessage(message.tempId!);
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
      final mins = remaining.inMinutes % 60;
      return mins > 0 ? '${remaining.inHours}h ${mins}m' : '${remaining.inHours}h';
    } else if (remaining.inMinutes > 0) {
      final secs = remaining.inSeconds % 60;
      return secs > 0 ? '${remaining.inMinutes}m ${secs}s' : '${remaining.inMinutes}m';
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
        ? (isDark ? RpgTheme.mineMsgBg : RpgTheme.mineMsgBgLight)
        : (isDark ? RpgTheme.theirsMsgBg : RpgTheme.theirsMsgBgLight);
    final borderColor = isMine
        ? (isDark ? RpgTheme.accentDark : RpgTheme.primaryLight)
        : (isDark ? RpgTheme.borderDark : RpgTheme.primaryLight);
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
          Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: EdgeInsets.only(
            left: isMine ? 48 : 0,
            right: isMine ? 0 : 48,
            bottom: 4,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            border: Border(
              left: BorderSide(
                color: borderColor,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.replyTo != null) ...[
              _buildReplyQuote(context, message.replyTo!, isDark, textColor, borderColor),
              const SizedBox(height: 8),
            ],
            // Message content based on type
            if (message.messageType == MessageType.text)
              _buildTextWithLinks(context, message.content, textColor)
            else if (message.messageType == MessageType.ping)
              Row(
                mainAxisSize: MainAxisSize.min,
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
                          '[Image failed to load]',
                          style: RpgTheme.bodyFont(fontSize: 12, color: Colors.red),
                        ),
                      );
                    },
                  ),
                ),
              )
            else
              Text(
                message.content.isNotEmpty ? message.content : '[Unsupported message type]',
                style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
              ),
            // Link preview card (shown for text messages with a URL)
            if (message.linkPreviewUrl != null)
              _buildLinkPreviewCard(context, isDark, textColor),
            // Retry button for failed messages
            Builder(
              builder: (ctx) {
                final retryBtn = _buildRetryButton(ctx);
                if (retryBtn == null) return const SizedBox.shrink();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    retryBtn,
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            // Bottom row: time + delivery + timer (ValueListenableBuilder avoids full-screen rebuild every second)
            Align(
              alignment: Alignment.bottomRight,
              child: ValueListenableBuilder<int>(
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
              ),
            ),
          ],
        ),
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

  Widget _buildTextWithLinks(BuildContext context, String text, Color textColor) {
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

    if (spans.isEmpty) {
      return Text(text, style: RpgTheme.bodyFont(fontSize: 14, color: textColor));
    }
    return RichText(text: TextSpan(children: spans));
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
              if (message.linkPreviewImageUrl != null)
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
                    ? RpgTheme.primaryColor(context).withValues(alpha: 0.15)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMine
                      ? RpgTheme.primaryColor(context)
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
