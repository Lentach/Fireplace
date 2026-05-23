import 'message_model.dart';
import 'user_model.dart';

class ConversationModel {
  final int id;
  final UserModel userOne;
  final UserModel userTwo;
  final DateTime createdAt;
  final int? disappearingTimer; // Timer in seconds, null = off
  final int? pinnedMessageId;
  final MessageModel? pinnedMessagePreview;

  ConversationModel({
    required this.id,
    required this.userOne,
    required this.userTwo,
    required this.createdAt,
    this.disappearingTimer,
    this.pinnedMessageId,
    this.pinnedMessagePreview,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as int,
      userOne: UserModel.fromJson(json['userOne'] as Map<String, dynamic>),
      userTwo: UserModel.fromJson(json['userTwo'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
      disappearingTimer: json['disappearingTimer'] as int?,
      pinnedMessageId: json['pinnedMessageId'] as int?,
      pinnedMessagePreview: json['pinnedMessage'] != null
          ? MessageModel.fromJson(json['pinnedMessage'] as Map<String, dynamic>)
          : null,
    );
  }
}
