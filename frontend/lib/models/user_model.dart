class UserModel {
  final int id;
  final String email;

  UserModel({required this.id, required this.email});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      email: json['email'] as String,
    );
  }
}
