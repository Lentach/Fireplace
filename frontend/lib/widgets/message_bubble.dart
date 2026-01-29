import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../theme/rpg_theme.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isMine ? RpgTheme.gold : RpgTheme.purple;
    final bgColor = isMine ? RpgTheme.mineMsgBg : RpgTheme.theirsMsgBg;
    final senderLabel = isMine
        ? '\u2694\uFE0F You'
        : '\u{1F6E1}\uFE0F ${message.senderEmail}';
    final senderColor = isMine ? RpgTheme.gold : RpgTheme.purple;

    final time = '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 350),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              senderLabel,
              style: RpgTheme.pressStart2P(fontSize: 7, color: senderColor),
            ),
            const SizedBox(height: 4),
            Text(
              message.content,
              style: RpgTheme.pressStart2P(fontSize: 8, color: RpgTheme.textColor),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                time,
                style: RpgTheme.pressStart2P(fontSize: 6, color: RpgTheme.timeColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
