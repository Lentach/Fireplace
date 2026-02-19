enum MessageDeliveryStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

enum MessageType {
  text,
  ping,
  image,
  drawing,
  voice,
}

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
      messageType: MessageModel._parseMessageType(json['messageType'] as String?),
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
  final MessageType messageType;
  final String? mediaUrl;
  final int? mediaDuration;
  final String? tempId; // For optimistic message matching
  final Map<String, List<int>> reactions; // emoji -> [userId]
  final int? replyToMessageId;
  final ReplyToPreview? replyTo;
  final String? linkPreviewUrl;
  final String? linkPreviewTitle;
  final String? linkPreviewImageUrl;

  MessageModel({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderUsername,
    required this.conversationId,
    required this.createdAt,
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.expiresAt,
    this.messageType = MessageType.text,
    this.mediaUrl,
    this.mediaDuration,
    this.tempId,
    this.reactions = const {},
    this.replyToMessageId,
    this.replyTo,
    this.linkPreviewUrl,
    this.linkPreviewTitle,
    this.linkPreviewImageUrl,
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
    );
  }

  static Map<String, List<int>> _parseReactions(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    return raw.map(
      (k, v) => MapEntry(k as String, (v as List).map((e) => e as int).toList()),
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

  static MessageType parseMessageType(String? type) => _parseMessageType(type);

  static MessageType _parseMessageType(String? type) {
    switch (type?.toUpperCase()) {
      case 'PING':
        return MessageType.ping;
      case 'IMAGE':
        return MessageType.image;
      case 'DRAWING':
        return MessageType.drawing;
      case 'VOICE':
        return MessageType.voice;
      default:
        return MessageType.text;
    }
  }

  MessageModel copyWith({
    MessageDeliveryStatus? deliveryStatus,
    DateTime? expiresAt,
    String? mediaUrl,
    int? mediaDuration,
    Map<String, List<int>>? reactions,
    int? replyToMessageId,
    ReplyToPreview? replyTo,
    String? linkPreviewUrl,
    String? linkPreviewTitle,
    String? linkPreviewImageUrl,
  }) {
    return MessageModel(
      id: id,
      content: content,
      senderId: senderId,
      senderUsername: senderUsername,
      conversationId: conversationId,
      createdAt: createdAt,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      expiresAt: expiresAt ?? this.expiresAt,
      messageType: messageType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaDuration: mediaDuration ?? this.mediaDuration,
      tempId: tempId,
      reactions: reactions ?? this.reactions,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyTo: replyTo ?? this.replyTo,
      linkPreviewUrl: linkPreviewUrl ?? this.linkPreviewUrl,
      linkPreviewTitle: linkPreviewTitle ?? this.linkPreviewTitle,
      linkPreviewImageUrl: linkPreviewImageUrl ?? this.linkPreviewImageUrl,
    );
  }
}
