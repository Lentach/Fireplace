import 'user_model.dart';

class ConversationModel {
  final int id;
  final UserModel userOne;
  final UserModel userTwo;
  final DateTime createdAt;

  ConversationModel({
    required this.id,
    required this.userOne,
    required this.userTwo,
    required this.createdAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as int,
      userOne: UserModel.fromJson(json['userOne'] as Map<String, dynamic>),
      userTwo: UserModel.fromJson(json['userTwo'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
