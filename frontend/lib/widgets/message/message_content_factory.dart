import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import 'file_message_content.dart';
import 'voice_message_content.dart';
import 'gif_message_content.dart';
import 'image_message_content.dart';
import 'ping_message_content.dart';
import 'text_message_content.dart';

/// Factory that picks the right content widget based on message type.
class MessageContentFactory {
  const MessageContentFactory._();

  static Widget build({
    required BuildContext context,
    required MessageModel message,
    required bool isMine,
    required bool isDark,
    required Color textColor,
    required double contentAreaWidth,
  }) {
    switch (message.messageType) {
      case MessageType.voice:
        return VoiceMessageContent(message: message, isMine: isMine);

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
        return ImageMessageContent(message: message);

      case MessageType.gif:
        return GifMessageContent(message: message);

      case MessageType.file:
        return FileMessageContent(
          message: message,
          textColor: textColor,
        );
    }
  }
}
