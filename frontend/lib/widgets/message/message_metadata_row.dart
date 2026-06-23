import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/messaging_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rpg_theme.dart';
import '../hearth_fade_arc.dart';

/// Timestamp + delivery icon + Hearth Fade ephemeral indicator (Telegram style).
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

  Widget _buildEphemeralIndicator() {
    if (!HearthFadeArcIndicator.showsEphemeralState(message)) {
      return const SizedBox.shrink();
    }

    final countdown = HearthFadeArcIndicator.countdownLabel(message);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 6),
        HearthFadeArcIndicator(
          message: message,
          color: timeColor,
          trackColor: timeColor.withValues(alpha: 0.28),
          size: 12,
        ),
        if (countdown != null) ...[
          const SizedBox(width: 3),
          Text(
            countdown,
            style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: context.read<MessagingProvider>().countdownTickNotifier,
      builder: (ctx, tick, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.editedAt != null) ...[
              Text(
                AppLocalizations.of(context).messageEditedLabel,
                style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              RpgTheme.formatMessageClock(message.createdAt),
              style: RpgTheme.bodyFont(fontSize: 10, color: timeColor),
            ),
            const SizedBox(width: 4),
            _buildDeliveryIcon(ctx),
            _buildEphemeralIndicator(),
          ],
        );
      },
    );
  }
}
