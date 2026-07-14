import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';
import '../theme/glass_theme.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../providers/messaging_provider.dart';
import '../providers/settings_provider.dart';
import 'avatar_circle.dart';
import 'glass/glass_dialog.dart';
import 'hearth_fade_arc.dart';
import '../utils/jumbo_emoji.dart';

class ConversationTile extends StatelessWidget {
  final int conversationId;
  final String displayName;
  final MessageModel? lastMessage;
  final bool isActive;
  final int unreadCount;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final UserModel? otherUser;
  final bool isTyping;

  const ConversationTile({
    super.key,
    required this.conversationId,
    required this.displayName,
    this.lastMessage,
    this.isActive = false,
    this.unreadCount = 0,
    this.isMuted = false,
    required this.onTap,
    required this.onDelete,
    this.otherUser,
    this.isTyping = false,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    final local = dt.toLocal();
    if (diff.inDays > 0) {
      return '${local.day}/${local.month}';
    }
    return RpgTheme.formatMessageClock(dt);
  }

  String _lastMessagePreview(BuildContext context, MessageModel lastMessage) {
    final l10n = AppLocalizations.of(context);
    if (lastMessage.messageType == MessageType.ping) return 'PING!';
    if (lastMessage.messageType == MessageType.voice) return l10n.voiceMessage;
    if (lastMessage.messageType == MessageType.image) {
      return l10n.attachment;
    }
    if (lastMessage.messageType == MessageType.gif) return 'GIF';
    if (lastMessage.messageType == MessageType.file) {
      return l10n.attachmentOptionDocument;
    }
    if (lastMessage.displayAsEncryptedPlaceholder ||
        lastMessage.content == 'Encrypted message') {
      return l10n.encryptedMessage;
    }
    return lastMessage.content;
  }

  String _ephemeralTooltip(BuildContext context, MessageModel message) {
    final l10n = AppLocalizations.of(context);
    final countdown = HearthFadeArcIndicator.countdownLabel(message);
    if (countdown != null) {
      return l10n.conversationLastMessageEphemeralRemaining(countdown);
    }
    return l10n.conversationLastMessageEphemeralPreRead;
  }

  Widget _buildEphemeralPrefix(
    BuildContext context,
    MessageModel message,
    Color ephemeralColor,
    Color secondaryColor,
  ) {
    return Tooltip(
      message: _ephemeralTooltip(context, message),
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: HearthFadeArcIndicator(
          message: message,
          color: ephemeralColor,
          trackColor: secondaryColor.withValues(alpha: 0.35),
          size: 12,
        ),
      ),
    );
  }

  Widget _buildTrailingMetaRow(
    BuildContext context,
    Color ephemeralColor,
    Color secondaryColor,
  ) {
    final staticTrailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMuted)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: AppLocalizations.of(context).userCardNotificationsMuted,
              child: Icon(
                Icons.notifications_off_outlined,
                size: 14,
                color: secondaryColor,
              ),
            ),
          ),
        if (unreadCount > 0)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            style: RpgTheme.bodyFont(fontSize: 11, color: secondaryColor),
          ),
      ],
    );

    final message = lastMessage;
    if (message == null ||
        !HearthFadeArcIndicator.showsEphemeralState(message)) {
      return staticTrailing;
    }

    return ValueListenableBuilder<int>(
      valueListenable: context.read<MessagingProvider>().countdownTickNotifier,
      child: staticTrailing,
      builder: (context, _, child) {
        if (!HearthFadeArcIndicator.showsEphemeralState(message)) {
          return child!;
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildEphemeralPrefix(
              context,
              message,
              ephemeralColor,
              secondaryColor,
            ),
            child!,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themePref = context.watch<SettingsProvider>().themePreference;
    final ephemeralColor = RpgTheme.ephemeralAccent(
      context,
      themePreference: themePref,
    );
    // Active-row tint comes from the glass theme so every theme highlights
    // with its own accent (spec: activeCapsule), not a hardcoded palette.
    final activeBg = GlassTheme.of(context).activeCapsule;
    // Per-theme muted (FireplaceColors) instead of the legacy warm gray that
    // tinted blue/teal dark themes orange-ish.
    final secondaryColor = FireplaceColors.of(context).mutedText;

    return Dismissible(
      key: ValueKey<int>(conversationId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete, color: Colors.white, size: 28),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final colorScheme = Theme.of(dialogContext).colorScheme;
            final isDark = RpgTheme.isDark(dialogContext);
            final mutedColor = isDark
                ? RpgTheme.mutedDark
                : RpgTheme.textSecondaryLight;
            final l10n = AppLocalizations.of(dialogContext);
            return GlassDialog(
              title: Text(
                l10n.deleteConversationTitle,
                style: RpgTheme.bodyFont(
                  fontSize: 16,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Text(
                l10n.deleteConversationConfirm,
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    l10n.cancel,
                    style: RpgTheme.bodyFont(fontSize: 14, color: mutedColor),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
                    l10n.delete,
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
          splashColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.2),
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
                          AppLocalizations.of(context).typing,
                          style: RpgTheme.bodyFont(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.primary,
                          ).copyWith(fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else if (lastMessage != null) ...[
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            children: buildInlineEmojiSpans(
                              _lastMessagePreview(context, lastMessage!),
                              textStyle: RpgTheme.bodyFont(
                                fontSize: 13,
                                color: secondaryColor,
                              ),
                              emojiFontSize: 13,
                            ),
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
                    _buildTrailingMetaRow(
                      context,
                      ephemeralColor,
                      secondaryColor,
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
