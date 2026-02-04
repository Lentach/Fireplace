import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import '../models/message_model.dart';

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

  Widget _buildDeliveryIcon() {
    if (!isMine) return const SizedBox.shrink();

    IconData icon;
    Color color;

    switch (message.deliveryStatus) {
      case MessageDeliveryStatus.sending:
        icon = Icons.access_time;
        color = Colors.grey;
        break;
      case MessageDeliveryStatus.sent:
        icon = Icons.check;
        color = Colors.grey;
        break;
      case MessageDeliveryStatus.delivered:
        icon = Icons.done_all;
        color = Colors.blue;
        break;
    }

    return Icon(icon, size: 12, color: color);
  }

  String? _getTimerText() {
    if (message.expiresAt == null) return null;

    final now = DateTime.now();
    final remaining = message.expiresAt!.difference(now);

    if (remaining.isNegative) return 'Expired';

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

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
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
            // Message content based on type
            if (message.messageType == MessageType.text)
              Text(
                message.content,
                style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
              )
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.mediaUrl!,
                  fit: BoxFit.cover,
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
              )
            else
              Text(
                message.content.isNotEmpty ? message.content : '[Unsupported message type]',
                style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
              ),
            const SizedBox(height: 4),
            // Bottom row: time + delivery + timer
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
                  ),
                  const SizedBox(width: 4),
                  _buildDeliveryIcon(),
                  if (_getTimerText() != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.timer_outlined, size: 10, color: timeColor),
                    const SizedBox(width: 2),
                    Text(
                      _getTimerText()!,
                      style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
