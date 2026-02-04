enum MessageDeliveryStatus {
  sending,
  sent,
  delivered,
}

enum MessageType {
  text,
  ping,
  image,
  drawing,
}

class MessageModel {
  final int id;
  final String content;
  final int senderId;
  final String senderEmail;
  final String? senderUsername;
  final int conversationId;
  final DateTime createdAt;
  final MessageDeliveryStatus deliveryStatus;
  final DateTime? expiresAt;
  final MessageType messageType;
  final String? mediaUrl;
  final String? tempId; // For optimistic message matching

  MessageModel({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderEmail,
    this.senderUsername,
    required this.conversationId,
    required this.createdAt,
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.expiresAt,
    this.messageType = MessageType.text,
    this.mediaUrl,
    this.tempId,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int,
      content: json['content'] as String? ?? '',
      senderId: json['senderId'] as int,
      senderEmail: json['senderEmail'] as String,
      senderUsername: json['senderUsername'] as String?,
      conversationId: json['conversationId'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      deliveryStatus: parseDeliveryStatus(json['deliveryStatus'] as String?),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      messageType: _parseMessageType(json['messageType'] as String?),
      mediaUrl: json['mediaUrl'] as String?,
      tempId: json['tempId'] as String?,
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
      case 'DRAWING':
        return MessageType.drawing;
      default:
        return MessageType.text;
    }
  }

  MessageModel copyWith({
    MessageDeliveryStatus? deliveryStatus,
    DateTime? expiresAt,
  }) {
    return MessageModel(
      id: id,
      content: content,
      senderId: senderId,
      senderEmail: senderEmail,
      senderUsername: senderUsername,
      conversationId: conversationId,
      createdAt: createdAt,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      expiresAt: expiresAt ?? this.expiresAt,
      messageType: messageType,
      mediaUrl: mediaUrl,
      tempId: tempId,
    );
  }
}
