class MessageModel {
  final int id;
  final String content;
  final int senderId;
  final String senderEmail;
  final String? senderUsername;
  final int conversationId;
  final DateTime createdAt;

  MessageModel({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderEmail,
    this.senderUsername,
    required this.conversationId,
    required this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int,
      content: json['content'] as String,
      senderId: json['senderId'] as int,
      senderEmail: json['senderEmail'] as String,
      senderUsername: json['senderUsername'] as String?,
      conversationId: json['conversationId'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
