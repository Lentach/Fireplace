import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import '../models/message_model.dart';
import 'avatar_circle.dart';

class ConversationTile extends StatelessWidget {
  final String displayName;
  final MessageModel? lastMessage;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ConversationTile({
    super.key,
    required this.displayName,
    this.lastMessage,
    this.isActive = false,
    required this.onTap,
    required this.onDelete,
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
    return Material(
      color: isActive ? RpgTheme.activeTabBg : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: RpgTheme.purple.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              AvatarCircle(email: displayName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: RpgTheme.bodyFont(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (lastMessage != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        lastMessage!.content,
                        style: RpgTheme.bodyFont(
                          fontSize: 13,
                          color: RpgTheme.mutedText,
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
                  if (lastMessage != null)
                    Text(
                      _formatTime(lastMessage!.createdAt),
                      style: RpgTheme.bodyFont(
                        fontSize: 11,
                        color: RpgTheme.timeColor,
                      ),
                    ),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: RpgTheme.logoutRed,
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Delete conversation',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
