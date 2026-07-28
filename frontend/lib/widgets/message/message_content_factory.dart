import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/message_model.dart';
import '../../providers/messaging_provider.dart';
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
          // Only TEXT rows can be mislabelled: keyed media legitimately keeps
          // content == "[encrypted]" forever (its payload is the mediaKey, not
          // text) and renders through the media widgets, so it can never pick
          // up a "Decrypting…" that would never resolve.
          decryptInProgress: _historyDecryptInFlight(context),
        );

      case MessageType.ping:
        return PingMessageContent(isMine: isMine, textColor: textColor);

      case MessageType.image:
        return ImageMessageContent(message: message);

      case MessageType.gif:
        return GifMessageContent(message: message);

      case MessageType.file:
        return FileMessageContent(message: message, textColor: textColor);
    }
  }
}

/// True while a history decrypt pass is running.
///
/// Falls back to false when there is no [MessagingProvider] above this widget —
/// bubbles are also rendered by previews and widget tests outside the app tree,
/// and a missing provider must degrade to the plain sentinel rather than throw.
bool _historyDecryptInFlight(BuildContext context) {
  try {
    return context.select<MessagingProvider, bool>(
      (m) => m.isDecryptingHistory,
    );
  } on ProviderNotFoundException {
    return false;
  }
}
