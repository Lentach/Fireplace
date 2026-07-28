import '../l10n/app_localizations.dart';
import '../models/message_model.dart';
import '../providers/encryption_provider.dart';

/// Server and client placeholders for E2E ciphertext rows.
bool isEncryptedPreviewContent(
  String content, {
  required String encryptedMessageLabel,
}) {
  if (content.isEmpty) return false;
  return content == '[encrypted]' ||
      content == encryptedMessageLabel ||
      content == kReplyPreviewLabels.encryptedMessageLabel;
}

bool hasUsablePlaintextContent(MessageModel message) {
  if (message.content.isEmpty) return false;
  if (message.content == '[encrypted]' ||
      message.content == '[Decryption failed]' ||
      message.content == '[Encryption not initialized]' ||
      message.content == '[Message no longer stored on this device]') {
    return false;
  }
  if (message.content == kReplyPreviewLabels.encryptedMessageLabel) {
    return false;
  }
  return true;
}

MessageModel? findMessageById(int id, Iterable<MessageModel>? messages) {
  if (messages == null) return null;
  for (final m in messages) {
    if (m.id == id) return m;
  }
  return null;
}

bool _serverPreviewNeedsLocalMerge(MessageModel server, MessageModel local) {
  if (hasUsablePlaintextContent(local) &&
      !hasUsablePlaintextContent(server)) {
    return true;
  }
  if (local.messageType != MessageType.text &&
      server.messageType == MessageType.text) {
    return true;
  }
  if ((local.mediaKey != null || local.mediaIv != null) &&
      local.mediaUrl != null &&
      (server.mediaKey == null || server.mediaUrl == null)) {
    return true;
  }
  return false;
}

/// Prefer a loaded chat row over a server pin/reply snapshot when it has readable text.
MessageModel resolvePinnedPreviewMessage({
  required MessageModel serverPreview,
  MessageModel? localMessage,
}) {
  if (localMessage == null || localMessage.id != serverPreview.id) {
    return serverPreview;
  }
  if (_serverPreviewNeedsLocalMerge(serverPreview, localMessage)) {
    return localMessage;
  }
  return serverPreview;
}

String? _decryptedPreviewText(EncryptionProvider? encryption, int messageId) {
  final cached = encryption?.getCachedDecryption(messageId);
  if (cached == null) return null;
  final text = cached.content;
  if (text.isEmpty ||
      text == '[encrypted]' ||
      text == '[Decryption failed]' ||
      text == '[Encryption not initialized]' ||
      text == '[Message no longer stored on this device]') {
    return null;
  }
  return text;
}

String _truncatePreview(String text) =>
    text.length > 150 ? '${text.substring(0, 150)}...' : text;

bool _isEncryptedRow(MessageModel message, String encryptedMessageLabel) =>
    message.content == '[encrypted]' ||
    (message.encryptedContent != null &&
        message.encryptedContent!.isNotEmpty &&
        isEncryptedPreviewContent(
          message.content,
          encryptedMessageLabel: encryptedMessageLabel,
        ));

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
  final decrypted = _decryptedPreviewText(encryption, message.id);
  if (decrypted != null && decrypted.isNotEmpty) {
    return _truncatePreview(decrypted);
  }

  final typeLabel = replyTypeLabel(
    message.messageType,
    voiceMessageLabel: voiceMessageLabel,
    imageLabel: imageLabel,
    gifLabel: gifLabel,
    documentLabel: documentLabel,
    pingLabel: pingLabel,
    encryptedMessageLabel: encryptedMessageLabel,
  );

  if (_isEncryptedRow(message, encryptedMessageLabel) ||
      isEncryptedPreviewContent(
        message.content,
        encryptedMessageLabel: encryptedMessageLabel,
      )) {
    if (message.messageType != MessageType.text) {
      return typeLabel;
    }
    return encryptedMessageLabel;
  }

  if (message.content.isNotEmpty) {
    return _truncatePreview(message.content);
  }
  return typeLabel;
}

String replyTypeLabel(
  MessageType type, {
  required String voiceMessageLabel,
  required String imageLabel,
  required String gifLabel,
  required String documentLabel,
  required String pingLabel,
  required String encryptedMessageLabel,
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
    case MessageType.text:
      return encryptedMessageLabel;
  }
}

String replyPreviewForMessage(
  AppLocalizations l10n,
  MessageModel message, {
  EncryptionProvider? encryption,
}) {
  if (message.content == '[Message no longer stored on this device]') {
    return l10n.messageNoLongerStoredOnThisDevice;
  }
  return replyPreviewForMessageModel(
    message,
    encryption: encryption,
    encryptedMessageLabel: l10n.encryptedMessage,
    voiceMessageLabel: l10n.voiceMessage,
    imageLabel: l10n.image,
    gifLabel: l10n.actionTileGif,
    documentLabel: l10n.attachmentOptionDocument,
    pingLabel: l10n.ping,
  );
}

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
  Iterable<MessageModel>? messagesForLookup,
}) {
  final quoted = findMessageById(replyTo.id, messagesForLookup);
  if (quoted != null) {
    final fromList = replyPreviewForMessage(l10n, quoted, encryption: encryption);
    if (fromList.isNotEmpty && fromList != l10n.encryptedMessage) {
      return fromList;
    }
  }
  if (replyTo.content == '[encrypted]' ||
      replyTo.content == l10n.encryptedMessage ||
      replyTo.content == kReplyPreviewLabels.encryptedMessageLabel) {
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
  Iterable<MessageModel>? messagesForLookup,
}) {
  final quoted = findMessageById(replyTo.id, messagesForLookup);
  if (quoted != null) {
    final fromList = replyPreviewForMessageModel(
      quoted,
      encryption: encryption,
      encryptedMessageLabel: encryptedMessageLabel,
      voiceMessageLabel: voiceMessageLabel,
      imageLabel: imageLabel,
      gifLabel: gifLabel,
      documentLabel: documentLabel,
      pingLabel: pingLabel,
    );
    if (fromList.isNotEmpty && fromList != encryptedMessageLabel) {
      return ReplyToPreview(
        id: replyTo.id,
        content: fromList,
        senderUsername: replyTo.senderUsername,
        messageType: quoted.messageType,
      );
    }
  }

  if (!isEncryptedPreviewContent(
    replyTo.content,
    encryptedMessageLabel: encryptedMessageLabel,
  )) {
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
      encryptedMessageLabel: encryptedMessageLabel,
    ),
    senderUsername: replyTo.senderUsername,
    messageType: replyTo.messageType,
  );
}

MessageModel enrichMessageReplyPreview(
  MessageModel message, {
  required EncryptionProvider? encryption,
  Iterable<MessageModel>? messagesForLookup,
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
    messagesForLookup: messagesForLookup,
  );
  if (identical(enriched, replyTo) || enriched.content == replyTo.content) {
    return message;
  }
  return message.copyWith(replyTo: enriched);
}
