import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';

class MessageDateSeparator extends StatelessWidget {
  final DateTime date;

  const MessageDateSeparator({super.key, required this.date});

  String _formatDate(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(messageDay).inDays;

    if (diff == 0) return l10n.chatDateToday;
    if (diff == 1) return l10n.chatDateYesterday;
    return MaterialLocalizations.of(context).formatShortDate(date);
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
              _formatDate(context),
              style: RpgTheme.bodyFont(fontSize: 11, color: textColor),
            ),
          ),
          Expanded(child: Divider(color: borderColor, thickness: 1)),
        ],
      ),
    );
  }
}
