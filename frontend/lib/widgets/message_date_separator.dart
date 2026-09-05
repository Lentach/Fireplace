import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/glass_theme.dart';
import '../theme/rpg_theme.dart';

class MessageDateSeparator extends StatelessWidget {
  final DateTime date;

  const MessageDateSeparator({super.key, required this.date});

  /// "Today" / "Yesterday" / short date for [date], device-local. Shared with
  /// the fullscreen video header so both surfaces name a day the same way.
  static String dayLabel(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final localDate = date.toLocal();
    final messageDay = DateTime(localDate.year, localDate.month, localDate.day);
    final diff = today.difference(messageDay).inDays;

    if (diff == 0) return l10n.chatDateToday;
    if (diff == 1) return l10n.chatDateYesterday;
    return MaterialLocalizations.of(context).formatShortDate(localDate);
  }

  String _formatDate(BuildContext context) => dayLabel(context, date);

  @override
  Widget build(BuildContext context) {
    // Liquid Glass spec §5: over the wallpaper a divider reads as noise —
    // dates sit in a solid centered mini-pill (content layer, NOT glass).
    final glass = GlassTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: glass.datePillBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _formatDate(context),
            style: RpgTheme.bodyFont(
              fontSize: 11,
              color: glass.datePillText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
