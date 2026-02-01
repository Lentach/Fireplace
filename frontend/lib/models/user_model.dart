class UserModel {
  final int id;
  final String email;
  final String? username;
  final String? profilePictureUrl;
  final bool? activeStatus;
  final bool? isOnline;

  UserModel({
    required this.id,
    required this.email,
    this.username,
    this.profilePictureUrl,
    this.activeStatus,
    this.isOnline,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String?,
      profilePictureUrl: json['profilePictureUrl'] as String?,
      activeStatus: json['activeStatus'] as bool?,
      isOnline: json['isOnline'] as bool?,
    );
  }

  UserModel copyWith({
    int? id,
    String? email,
    String? username,
    String? profilePictureUrl,
    bool? activeStatus,
    bool? isOnline,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      activeStatus: activeStatus ?? this.activeStatus,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
