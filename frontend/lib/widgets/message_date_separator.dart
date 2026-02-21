import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class MessageDateSeparator extends StatelessWidget {
  final DateTime date;

  const MessageDateSeparator({super.key, required this.date});

  String _formatDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(messageDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final borderColor =
        FireplaceColors.of(context).convItemBorder;
    final textColor =
        isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: borderColor, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formatDate(),
              style: RpgTheme.bodyFont(fontSize: 11, color: textColor),
            ),
          ),
          Expanded(child: Divider(color: borderColor, thickness: 1)),
        ],
      ),
    );
  }
}
