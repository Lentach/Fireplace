import '../l10n/app_localizations.dart';
import '../models/message_model.dart';
import '../providers/encryption_provider.dart';

String? _decryptedPreviewText(EncryptionProvider? encryption, int messageId) {
  final cached = encryption?.getCachedDecryption(messageId);
  if (cached == null) return null;
  final text = cached.content;
  if (text.isEmpty ||
      text == '[encrypted]' ||
      text == '[Decryption failed]' ||
      text == '[Encryption not initialized]') {
    return null;
  }
  return text;
}

/// Context-free helper for provider/tests — required for media sends.
String replyPreviewForMessageModel(
  MessageModel message, {
  EncryptionProvider? encryption,
  required String encryptedMessageLabel,
  required String voiceMessageLabel,
  required String imageLabel,
  required String gifLabel,
  required String documentLabel,
  required String pingLabel,
}) {
  if (message.content == '[encrypted]') {
    final decrypted = _decryptedPreviewText(encryption, message.id);
    if (decrypted != null && decrypted.isNotEmpty) {
      return decrypted.length > 150
          ? '${decrypted.substring(0, 150)}...'
          : decrypted;
    }
    return encryptedMessageLabel;
  }
  if (message.content.isNotEmpty) {
    return message.content.length > 150
        ? '${message.content.substring(0, 150)}...'
        : message.content;
  }
  return replyTypeLabel(
    message.messageType,
    voiceMessageLabel: voiceMessageLabel,
    imageLabel: imageLabel,
    gifLabel: gifLabel,
    documentLabel: documentLabel,
    pingLabel: pingLabel,
  );
}

String replyTypeLabel(
  MessageType type, {
  required String voiceMessageLabel,
  required String imageLabel,
  required String gifLabel,
  required String documentLabel,
  required String pingLabel,
}) {
  switch (type) {
    case MessageType.voice:
      return voiceMessageLabel;
    case MessageType.image:
      return imageLabel;
    case MessageType.gif:
      return gifLabel;
    case MessageType.file:
      return documentLabel;
    case MessageType.ping:
      return pingLabel;
    default:
      return '';
  }
}

String replyPreviewForMessage(
  AppLocalizations l10n,
  MessageModel message, {
  EncryptionProvider? encryption,
}) =>
    replyPreviewForMessageModel(
      message,
      encryption: encryption,
      encryptedMessageLabel: l10n.encryptedMessage,
      voiceMessageLabel: l10n.voiceMessage,
      imageLabel: l10n.image,
      gifLabel: l10n.actionTileGif,
      documentLabel: l10n.attachmentOptionDocument,
      pingLabel: l10n.ping,
    );

/// Default English labels for provider paths without BuildContext.
const kReplyPreviewLabels = (
  encryptedMessageLabel: 'Encrypted message',
  voiceMessageLabel: 'Voice message',
  imageLabel: 'Image',
  gifLabel: 'GIF',
  documentLabel: 'Document',
  pingLabel: 'Ping',
);

String replyDisplayContentForQuote(
  AppLocalizations l10n,
  ReplyToPreview replyTo, {
  EncryptionProvider? encryption,
  required int conversationId,
  required DateTime createdAt,
}) {
  if (replyTo.content == '[encrypted]' ||
      replyTo.content == l10n.encryptedMessage) {
    final decrypted = encryption?.getCachedDecryption(replyTo.id)?.content;
    if (decrypted != null &&
        decrypted.isNotEmpty &&
        decrypted != '[encrypted]' &&
        decrypted != '[Decryption failed]') {
      return decrypted.length > 150
          ? '${decrypted.substring(0, 150)}...'
          : decrypted;
    }
  }
  return replyPreviewForMessage(
    l10n,
    MessageModel(
      id: replyTo.id,
      content: replyTo.content,
      senderId: 0,
      senderUsername: replyTo.senderUsername,
      conversationId: conversationId,
      createdAt: createdAt,
      messageType: replyTo.messageType,
    ),
    encryption: encryption,
  );
}

ReplyToPreview enrichReplyToPreview(
  ReplyToPreview replyTo, {
  required EncryptionProvider? encryption,
  required String encryptedMessageLabel,
  required String voiceMessageLabel,
  required String imageLabel,
  required String gifLabel,
  required String documentLabel,
  required String pingLabel,
}) {
  if (replyTo.content != '[encrypted]' &&
      replyTo.content != encryptedMessageLabel) {
    return replyTo;
  }
  final decrypted = _decryptedPreviewText(encryption, replyTo.id);
  if (decrypted != null && decrypted.isNotEmpty) {
    return ReplyToPreview(
      id: replyTo.id,
      content: decrypted.length > 150
          ? '${decrypted.substring(0, 150)}...'
          : decrypted,
      senderUsername: replyTo.senderUsername,
      messageType: replyTo.messageType,
    );
  }
  return ReplyToPreview(
    id: replyTo.id,
    content: replyTypeLabel(
      replyTo.messageType,
      voiceMessageLabel: voiceMessageLabel,
      imageLabel: imageLabel,
      gifLabel: gifLabel,
      documentLabel: documentLabel,
      pingLabel: pingLabel,
    ),
    senderUsername: replyTo.senderUsername,
    messageType: replyTo.messageType,
  );
}

MessageModel enrichMessageReplyPreview(
  MessageModel message, {
  required EncryptionProvider? encryption,
}) {
  final replyTo = message.replyTo;
  if (replyTo == null) return message;
  final labels = kReplyPreviewLabels;
  final enriched = enrichReplyToPreview(
    replyTo,
    encryption: encryption,
    encryptedMessageLabel: labels.encryptedMessageLabel,
    voiceMessageLabel: labels.voiceMessageLabel,
    imageLabel: labels.imageLabel,
    gifLabel: labels.gifLabel,
    documentLabel: labels.documentLabel,
    pingLabel: labels.pingLabel,
  );
  if (identical(enriched, replyTo) || enriched.content == replyTo.content) {
    return message;
  }
  return message.copyWith(replyTo: enriched);
}
