class UserModel {
  final int id;
  final String email;
  final String? username;
  final String? profilePictureUrl;

  UserModel({
    required this.id,
    required this.email,
    this.username,
    this.profilePictureUrl,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String?,
      profilePictureUrl: json['profilePictureUrl'] as String?,
    );
  }

  UserModel copyWith({
    int? id,
    String? email,
    String? username,
    String? profilePictureUrl,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
    );
  }
}
