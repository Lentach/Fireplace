import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/message_model.dart';
import '../../theme/rpg_theme.dart';
import '../voice_message_bubble.dart';
import 'file_message_content.dart';
import 'gif_message_content.dart';
import 'image_message_content.dart';
import 'ping_message_content.dart';
import 'text_message_content.dart';

/// Factory that picks the right content widget based on message type.
class MessageContentFactory {
  const MessageContentFactory._();

  static String displayContent(BuildContext context, MessageModel message) {
    final l10n = AppLocalizations.of(context);
    if (message.content == '[Decryption failed]') return l10n.decryptionFailed;
    if (message.content == '[Encryption not initialized]') return l10n.encryptionNotInitialized;
    if (message.content.isNotEmpty) return message.content;
    return l10n.unsupportedMessageType;
  }

  static Widget build({
    required BuildContext context,
    required MessageModel message,
    required bool isMine,
    required bool isDark,
    required Color textColor,
    required double contentAreaWidth,
  }) {
    // Voice is handled by its own dedicated bubble widget
    if (message.messageType == MessageType.voice) {
      return VoiceMessageBubble(message: message, isMine: isMine);
    }

    switch (message.messageType) {
      case MessageType.text:
        return TextMessageContent(
          message: message,
          isMine: isMine,
          textColor: textColor,
          isDark: isDark,
          maxWidth: contentAreaWidth,
        );

      case MessageType.ping:
        return PingMessageContent(isMine: isMine, textColor: textColor);

      case MessageType.image:
        return ImageMessageContent(mediaUrl: message.mediaUrl);

      case MessageType.gif:
        return GifMessageContent(mediaUrl: message.mediaUrl);

      case MessageType.file:
        return FileMessageContent(
          mediaUrl: message.mediaUrl,
          content: message.content,
          textColor: textColor,
        );

      default:
        // Fallback for unknown/unsupported types
        final text = displayContent(context, message);
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
            textAlign: isMine ? TextAlign.right : TextAlign.left,
          ),
        );
    }
  }
}
