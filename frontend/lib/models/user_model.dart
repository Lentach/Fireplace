class UserModel {
  final int id;
  final String email;
  final String? username;

  UserModel({required this.id, required this.email, this.username});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String?,
    );
  }
}
