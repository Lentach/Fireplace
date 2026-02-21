import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'avatar_circle.dart';

class ConversationTile extends StatelessWidget {
  final String displayName;
  final MessageModel? lastMessage;
  final bool isActive;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final UserModel? otherUser;
  final bool isTyping;

  const ConversationTile({
    super.key,
    required this.displayName,
    this.lastMessage,
    this.isActive = false,
    this.unreadCount = 0,
    required this.onTap,
    required this.onDelete,
    this.otherUser,
    this.isTyping = false,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 0) {
      return '${dt.day}/${dt.month}';
    }
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final activeBg = isDark ? RpgTheme.activeTabBgDark : RpgTheme.activeTabBgLight;
    final secondaryColor = isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;

    return Dismissible(
      key: Key('conv-tile-$displayName'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
          size: 28,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final colorScheme = Theme.of(dialogContext).colorScheme;
            final isDark = RpgTheme.isDark(dialogContext);
            final mutedColor =
                isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight;
            return AlertDialog(
              backgroundColor: colorScheme.surface,
              title: Text(
                'Delete Conversation?',
                style: RpgTheme.bodyFont(
                  fontSize: 16,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Text(
                'This will delete all messages in this conversation. You can re-open the chat later from Contacts.',
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    'Cancel',
                    style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
                    'Delete',
                    style: RpgTheme.bodyFont(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) => onDelete(),
      child: Material(
      color: isActive ? activeBg : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              AvatarCircle(
                displayName: displayName,
                profilePictureUrl: otherUser?.profilePictureUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: RpgTheme.bodyFont(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isTyping) ...[
                      const SizedBox(height: 3),
                      Text(
                        'typing...',
                        style: RpgTheme.bodyFont(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                        ).copyWith(fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (lastMessage != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        lastMessage!.messageType == MessageType.ping
                            ? 'PING!'
                            : lastMessage!.messageType == MessageType.voice
                                ? 'Voice message'
                                : lastMessage!.content,
                        style: RpgTheme.bodyFont(
                          fontSize: 13,
                          color: secondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: RpgTheme.bodyFont(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (lastMessage != null)
                        Text(
                          _formatTime(lastMessage!.createdAt),
                          style: RpgTheme.bodyFont(
                            fontSize: 11,
                            color: secondaryColor,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
