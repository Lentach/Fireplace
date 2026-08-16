enum MessageDeliveryStatus { sending, sent, delivered, read, failed }

enum MessageType { text, ping, image, voice, gif, file, video }

/// Preview of a message being replied to (sent in payload).
class ReplyToPreview {
  final int id;
  final String content;
  final String senderUsername;
  final MessageType messageType;

  const ReplyToPreview({
    required this.id,
    required this.content,
    required this.senderUsername,
    required this.messageType,
  });

  factory ReplyToPreview.fromJson(Map<String, dynamic> json) {
    return ReplyToPreview(
      id: json['id'] as int,
      content: json['content'] as String? ?? '',
      senderUsername: json['senderUsername'] as String? ?? '',
      messageType: MessageModel._parseMessageType(
        json['messageType'] as String?,
      ),
    );
  }
}

class MessageModel {
  final int id;
  final String content;
  final int senderId;
  final String senderUsername;
  final int conversationId;
  final DateTime createdAt;
  final MessageDeliveryStatus deliveryStatus;
  final DateTime? expiresAt;

  /// TTL frozen at send; countdown starts when recipient reads.
  final int? disappearAfterSeconds;
  final MessageType messageType;
  final String? mediaUrl;
  final int? mediaDuration;

  /// Intrinsic encrypted media geometry from the E2E envelope — client-only.
  final int? mediaWidth;

  /// Intrinsic encrypted media geometry from the E2E envelope — client-only.
  final int? mediaHeight;

  /// Compact encrypted visual placeholder from the E2E envelope — client-only.
  final String? mediaThumbHash;
  final String? tempId; // For optimistic message matching
  final Map<String, List<int>> reactions; // emoji -> [userId]
  final int? replyToMessageId;
  final ReplyToPreview? replyTo;
  final String? linkPreviewUrl;
  final String? linkPreviewTitle;
  final String? linkPreviewImageUrl;
  final String? encryptedContent;

  /// AES-256-GCM key (base64), from E2E envelope — client-only, not from REST.
  final String? mediaKey;

  /// AES-256-GCM IV (base64), from E2E envelope — client-only.
  final String? mediaIv;

  /// Server-stamped time of the last edit; null = never edited. From REST/WS payload.
  final DateTime? editedAt;

  /// True if this message has E2E encrypted content and was sent by another
  /// user (needs decryption before display).
  bool needsDecryption(int? currentUserId) =>
      encryptedContent != null &&
      encryptedContent!.isNotEmpty &&
      senderId != currentUserId;

  /// True if this message should show "Encrypted message" placeholder in list.
  bool get displayAsEncryptedPlaceholder =>
      encryptedContent != null &&
      encryptedContent!.isNotEmpty &&
      content == '[encrypted]';

  /// True when this is a TEXT message whose [content] is real plaintext —
  /// i.e. safe to offer "Copy" in the context menu. The bracket labels are
  /// the E2E placeholder / terminal states (same literals used by
  /// ChatMessageBubble._displayContent and reply_preview_helper.dart).
  bool get hasCopyablePlaintext =>
      messageType == MessageType.text &&
      content.isNotEmpty &&
      content != '[encrypted]' &&
      content != '[Decryption failed]' &&
      content != '[Encryption not initialized]' &&
      content != '[Message no longer stored on this device]';

  MessageModel({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderUsername,
    required this.conversationId,
    required this.createdAt,
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.expiresAt,
    this.disappearAfterSeconds,
    this.messageType = MessageType.text,
    this.mediaUrl,
    this.mediaDuration,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaThumbHash,
    this.tempId,
    this.reactions = const {},
    this.replyToMessageId,
    this.replyTo,
    this.linkPreviewUrl,
    this.linkPreviewTitle,
    this.linkPreviewImageUrl,
    this.encryptedContent,
    this.mediaKey,
    this.mediaIv,
    this.editedAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int,
      content: json['content'] as String? ?? '',
      senderId: json['senderId'] as int,
      senderUsername: json['senderUsername'] as String? ?? '',
      conversationId: json['conversationId'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      deliveryStatus: parseDeliveryStatus(json['deliveryStatus'] as String?),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      disappearAfterSeconds: json['disappearAfterSeconds'] != null
          ? (json['disappearAfterSeconds'] as num).toInt()
          : null,
      messageType: _parseMessageType(json['messageType'] as String?),
      mediaUrl: json['mediaUrl'] as String?,
      mediaDuration: json['mediaDuration'] != null
          ? (json['mediaDuration'] as num).round()
          : null,
      tempId: json['tempId'] as String?,
      reactions: _parseReactions(json['reactions']),
      replyToMessageId: json['replyToMessageId'] != null
          ? (json['replyToMessageId'] as num).toInt()
          : null,
      replyTo: json['replyTo'] != null
          ? ReplyToPreview.fromJson(json['replyTo'] as Map<String, dynamic>)
          : null,
      linkPreviewUrl: json['linkPreviewUrl'] as String?,
      linkPreviewTitle: json['linkPreviewTitle'] as String?,
      linkPreviewImageUrl: json['linkPreviewImageUrl'] as String?,
      encryptedContent: json['encryptedContent'] as String?,
      editedAt: json['editedAt'] != null
          ? DateTime.parse(json['editedAt'] as String)
          : null,
    );
  }

  static Map<String, List<int>> _parseReactions(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    return raw.map(
      (k, v) =>
          MapEntry(k as String, (v as List).map((e) => e as int).toList()),
    );
  }

  // Public method for parsing delivery status from other files
  static MessageDeliveryStatus parseDeliveryStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'SENDING':
        return MessageDeliveryStatus.sending;
      case 'SENT':
        return MessageDeliveryStatus.sent;
      case 'DELIVERED':
        return MessageDeliveryStatus.delivered;
      case 'READ':
        return MessageDeliveryStatus.read;
      case 'FAILED':
        return MessageDeliveryStatus.failed;
      default:
        return MessageDeliveryStatus.sent;
    }
  }

  static MessageType _parseMessageType(String? type) {
    switch (type?.toUpperCase()) {
      case 'PING':
        return MessageType.ping;
      case 'IMAGE':
        return MessageType.image;
      case 'VOICE':
        return MessageType.voice;
      case 'GIF':
        return MessageType.gif;
      case 'FILE':
        return MessageType.file;
      case 'VIDEO':
        return MessageType.video;
      default:
        return MessageType.text;
    }
  }

  MessageModel copyWith({
    MessageType? messageType,
    String? content,
    MessageDeliveryStatus? deliveryStatus,
    DateTime? expiresAt,
    int? disappearAfterSeconds,
    String? mediaUrl,
    int? mediaDuration,
    int? mediaWidth,
    int? mediaHeight,
    String? mediaThumbHash,
    Map<String, List<int>>? reactions,
    int? replyToMessageId,
    ReplyToPreview? replyTo,
    String? linkPreviewUrl,
    String? linkPreviewTitle,
    String? linkPreviewImageUrl,
    String? encryptedContent,
    String? mediaKey,
    String? mediaIv,
    DateTime? editedAt,
  }) {
    return MessageModel(
      id: id,
      content: content ?? this.content,
      senderId: senderId,
      senderUsername: senderUsername,
      conversationId: conversationId,
      createdAt: createdAt,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      expiresAt: expiresAt ?? this.expiresAt,
      disappearAfterSeconds:
          disappearAfterSeconds ?? this.disappearAfterSeconds,
      messageType: messageType ?? this.messageType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaDuration: mediaDuration ?? this.mediaDuration,
      mediaWidth: mediaWidth ?? this.mediaWidth,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      mediaThumbHash: mediaThumbHash ?? this.mediaThumbHash,
      tempId: tempId,
      reactions: reactions ?? this.reactions,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyTo: replyTo ?? this.replyTo,
      linkPreviewUrl: linkPreviewUrl ?? this.linkPreviewUrl,
      linkPreviewTitle: linkPreviewTitle ?? this.linkPreviewTitle,
      linkPreviewImageUrl: linkPreviewImageUrl ?? this.linkPreviewImageUrl,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      mediaKey: mediaKey ?? this.mediaKey,
      mediaIv: mediaIv ?? this.mediaIv,
      editedAt: editedAt ?? this.editedAt,
    );
  }
}
