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

  @override
  Widget build(BuildContext context) {
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
          color: isMine ? RpgTheme.mineMsgBg : RpgTheme.theirsMsgBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          border: Border(
            left: BorderSide(
              color: isMine ? RpgTheme.gold : RpgTheme.purple,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: RpgTheme.bodyFont(fontSize: 14, color: RpgTheme.textColor),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                _formatTime(message.createdAt),
                style: RpgTheme.bodyFont(fontSize: 10, color: RpgTheme.timeColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
