import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/message_model.dart';
import '../../providers/messaging_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rpg_theme.dart';

/// Timestamp + delivery icon + countdown timer row (Telegram style).
class MessageMetadataRow extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final Color timeColor;

  const MessageMetadataRow({
    super.key,
    required this.message,
    required this.isMine,
    required this.timeColor,
  });

  String? _getTimerText() {
    if (message.expiresAt == null) return null;
    final now = DateTime.now();
    final remaining = message.expiresAt!.difference(now);
    if (remaining.isNegative) return null;
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m';
    } else {
      return '${remaining.inSeconds}s';
    }
  }

  /// One check = delivered. Two checks = read.
  /// Icon colors follow bubble luminance (see [RpgTheme.messageBubbleDeliveryTickColors]).
  Widget _buildDeliveryIcon(BuildContext context) {
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

    final tickPref = context.read<SettingsProvider>().themePreference;
    final ticks = RpgTheme.messageBubbleDeliveryTickColors(
      context,
      isMine: isMine,
      themePreference: tickPref,
    );
    final color = message.deliveryStatus == MessageDeliveryStatus.read
        ? ticks.$2
        : ticks.$1;
    return Icon(icon, size: 12, color: color);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: context.read<MessagingProvider>().countdownTickNotifier,
      builder: (ctx, tick, child) {
        final timerText = _getTimerText();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              RpgTheme.formatMessageClock(message.createdAt),
              style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
            ),
            const SizedBox(width: 4),
            _buildDeliveryIcon(ctx),
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
    );
  }
}
