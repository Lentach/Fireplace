import 'user_model.dart';

class FriendRequestModel {
  final int id;
  final UserModel sender;
  final UserModel receiver;
  final String status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  FriendRequestModel({
    required this.id,
    required this.sender,
    required this.receiver,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory FriendRequestModel.fromJson(Map<String, dynamic> json) {
    return FriendRequestModel(
      id: json['id'] as int,
      sender: UserModel.fromJson(json['sender'] as Map<String, dynamic>),
      receiver: UserModel.fromJson(json['receiver'] as Map<String, dynamic>),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      respondedAt: json['respondedAt'] != null
          ? DateTime.parse(json['respondedAt'] as String)
          : null,
    );
  }
}
