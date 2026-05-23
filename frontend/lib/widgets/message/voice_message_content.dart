import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/messaging_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/message_expiry.dart';
import '../audio/playback_controller.dart';
import '../audio/waveform_display.dart';
import '../hearth_fade_arc.dart';
import '../message_swipe_wrapper.dart';
import '../dialogs/message_delete_dialog.dart';
import 'message_context_menu_overlay.dart';
import 'reaction_chips_row.dart';

/// Full voice-message bubble: outer bubble shell + PlaybackController + WaveformDisplay.
///
/// Extracted from the monolithic voice_message_bubble.dart. Visual output is
/// identical — only the internal organisation has changed.
class VoiceMessageContent extends StatelessWidget {
  final MessageModel message;
  final bool isMine;

  const VoiceMessageContent({
    super.key,
    required this.message,
    required this.isMine,
  });

  // ── helpers ──────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  bool _isExpired() => isMessageExpired(message);

  Widget _buildEphemeralMeta(Color metaColor) {
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
          color: metaColor,
          trackColor: metaColor.withValues(alpha: 0.28),
          size: 12,
        ),
        if (countdown != null) ...[
          const SizedBox(width: 3),
          Text(
            countdown,
            style: RpgTheme.bodyFont(fontSize: 10, color: metaColor),
          ),
        ],
      ],
    );
  }

  void _openContextMenu(BuildContext context) {
    final messaging = context.read<MessagingProvider>();
    final auth = context.read<AuthProvider>();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    openMessageContextMenu(
      context: context,
      message: message,
      bubbleRenderBox: renderBox,
      isMine: isMine,
      currentUserId: auth.currentUser?.id,
      onReply: () => messaging.setReplyingTo(message),
      onPin: () {
        if (message.id > 0) {
          messaging.pinMessage(message.conversationId, message.id);
        }
      },
      onDelete: () {
        showMessageDeleteDialog(
          context: context,
          isMine: isMine,
          messageId: message.id,
          onDeleteForMe: () =>
              messaging.deleteMessage(message.id, forEveryone: false),
          onDeleteForEveryone: () =>
              messaging.deleteMessage(message.id, forEveryone: true),
        );
      },
      onReaction: (emoji, alreadyReacted) {
        if (alreadyReacted) {
          messaging.removeReaction(message.id, emoji);
        } else {
          messaging.addReaction(message.id, emoji);
        }
      },
    );
  }

  // ── reply quote ───────────────────────────────────────────────────────────

  Widget _buildReplyQuote(
    BuildContext context,
    ReplyToPreview replyTo,
    bool isDark,
    Color borderColor,
  ) {
    final l10n = AppLocalizations.of(context);
    final mutedColor = isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight;
    String content = replyTo.content == '[encrypted]'
        ? l10n.encryptedMessage
        : replyTo.content;
    if (content.isEmpty) {
      switch (replyTo.messageType) {
        case MessageType.voice:
          content = l10n.voiceMessage;
          break;
        case MessageType.image:
          content = l10n.image;
          break;
        case MessageType.ping:
          content = l10n.ping;
          break;
        default:
          content = '';
      }
    }
    return Container(
      padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6, right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: borderColor, width: 3)),
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            replyTo.senderUsername.isNotEmpty ? replyTo.senderUsername : l10n.unknown,
            style: RpgTheme.bodyFont(
              fontSize: 12,
              color: borderColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              content,
              style: RpgTheme.bodyFont(fontSize: 12, color: mutedColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // ── delivery icon ─────────────────────────────────────────────────────────

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
      default:
        icon = Icons.check;
    }
    final pref = context.read<SettingsProvider>().themePreference;
    final ticks = RpgTheme.messageBubbleDeliveryTickColors(
      context,
      isMine: isMine,
      themePreference: pref,
    );
    final color = message.deliveryStatus == MessageDeliveryStatus.read
        ? ticks.$2
        : ticks.$1;
    return Icon(icon, size: 12, color: color);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final bubbleColor = isMine
        ? FireplaceColors.of(context).mineMsgBg
        : FireplaceColors.of(context).theirsMsgBg;
    final themePreference = context.read<SettingsProvider>().themePreference;
    final borderColor = isMine
        ? Theme.of(context).colorScheme.primary
        : FireplaceColors.of(context).borderColor;
    final waveformColor = isMine && !isDark && themePreference == 'light'
        ? RpgTheme.textSecondaryLight
        : (isMine && themePreference == 'teal'
            ? Colors.white.withValues(alpha: 0.82)
            : borderColor);
    final metaColor = RpgTheme.messageBubbleMetaColor(
      context,
      isMine: isMine,
      themePreference: themePreference,
    );
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    final messaging = context.read<MessagingProvider>();

    return MessageSwipeWrapper(
      isMine: isMine,
      onSwipeReply: () => messaging.setReplyingTo(message),
      onLongPress: () => _openContextMenu(context),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(top: message.reactions.isNotEmpty ? 14.0 : 0.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.6,
                ),
                margin: EdgeInsets.only(
                  left: isMine ? 48 : 0,
                  right: isMine ? 0 : 48,
                  bottom: 10,
                ),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: PlaybackController(
                  message: message,
                  builder: (
                    context,
                    isPlaying,
                    isLoading,
                    position,
                    duration,
                    speed,
                    togglePlayPause,
                    seekFromWaveform,
                    toggleSpeed,
                  ) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.replyTo != null) ...[
                          _buildReplyQuote(context, message.replyTo!, isDark, borderColor),
                          const SizedBox(height: 8),
                        ],

                        // Playback controls row
                        Row(
                          children: [
                            // Play/Pause (or loading spinner with tap-to-cancel)
                            isLoading
                                ? GestureDetector(
                                    onTap: togglePlayPause,
                                    child: SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: isMine && !isDark && themePreference == 'light'
                                            ? RpgTheme.textSecondaryLight
                                            : (isMine && themePreference == 'teal'
                                                ? Colors.white.withValues(alpha: 0.85)
                                                : null),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                                    onPressed: _isExpired() ? null : togglePlayPause,
                                    iconSize: 32,
                                    color: _isExpired()
                                        ? Colors.grey
                                        : (isMine && !isDark && themePreference == 'light'
                                            ? RpgTheme.textColorLight
                                            : (isMine && themePreference == 'teal'
                                                ? Colors.white
                                                : null)),
                                  ),

                            const SizedBox(width: 8),

                            // Waveform: scrubbable (tap/drag to seek)
                            Expanded(
                              child: WaveformDisplay(
                                messageId: message.id,
                                position: position,
                                duration: duration,
                                color: waveformColor,
                                onSeek: seekFromWaveform,
                              ),
                            ),

                            const SizedBox(width: 4),

                            // Position / total duration
                            Text(
                              '${_formatDuration(position)}/${_formatDuration(duration)}',
                              style: RpgTheme.bodyFont(fontSize: 10, color: metaColor),
                            ),

                            const SizedBox(width: 6),

                            // Speed toggle: 1x → 1.5x → 2x → 1x
                            InkWell(
                              onTap: toggleSpeed,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: waveformColor),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${speed}x',
                                  style: RpgTheme.bodyFont(fontSize: 11, color: metaColor),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                RpgTheme.formatMessageClock(message.createdAt),
                                style: RpgTheme.bodyFont(
                                  fontSize: 10,
                                  color: metaColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              _buildDeliveryIcon(context),
                              ValueListenableBuilder<int>(
                                valueListenable: context
                                    .read<MessagingProvider>()
                                    .countdownTickNotifier,
                                builder: (context, tick, child) =>
                                    _buildEphemeralMeta(metaColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (message.reactions.isNotEmpty)
                Positioned(
                  top: -14,
                  left: isMine ? null : 8,
                  right: isMine ? 8 : null,
                  child: ReactionChipsRow(
                    reactions: message.reactions,
                    currentUserId: currentUserId ?? -1,
                    onTap: (emoji, isMyReaction) {
                      final msg = context.read<MessagingProvider>();
                      if (isMyReaction) {
                        msg.removeReaction(message.id, emoji);
                      } else {
                        msg.addReaction(message.id, emoji);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
