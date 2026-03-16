import 'package:flutter/material.dart';

import '../../models/message_model.dart';
import '../../theme/rpg_theme.dart';

/// Displays the quoted reply preview above the input bar.
/// Shows sender name, content preview, and a dismiss button.
class ReplyPreviewBar extends StatelessWidget {
  const ReplyPreviewBar({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final MessageModel message;
  final VoidCallback onDismiss;

  String _contentPreview() {
    switch (message.messageType) {
      case MessageType.voice:
        return 'Voice message';
      case MessageType.image:
        return 'Image';
      case MessageType.gif:
        return 'GIF';
      case MessageType.file:
        return message.content.isNotEmpty ? message.content : 'Document';
      case MessageType.ping:
        return 'Ping';
      default:
        return message.content.length > 80
            ? '${message.content.substring(0, 80)}...'
            : message.content;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final fc = FireplaceColors.of(context);
    final borderColor = Theme.of(context).colorScheme.primary;
    final mutedColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        border: Border(
          left: BorderSide(color: borderColor, width: 4),
          bottom: BorderSide(color: fc.tabBorder),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.senderUsername.isNotEmpty
                      ? message.senderUsername
                      : 'Unknown',
                  style: RpgTheme.bodyFont(
                    fontSize: 12,
                    color: borderColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _contentPreview(),
                  style: RpgTheme.bodyFont(fontSize: 12, color: mutedColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            color: mutedColor,
          ),
        ],
      ),
    );
  }
}
