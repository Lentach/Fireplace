class UserProfilePhoto {
  final int id;
  final String url;
  final bool isPrimary;
  final DateTime createdAt;

  const UserProfilePhoto({
    required this.id,
    required this.url,
    required this.isPrimary,
    required this.createdAt,
  });

  factory UserProfilePhoto.fromJson(Map<String, dynamic> json) {
    return UserProfilePhoto(
      id: json['id'] as int,
      url: json['url'] as String,
      isPrimary: json['isPrimary'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class UserModel {
  final int id;
  final String username;
  final String tag;
  final String? profilePictureUrl;
  final List<UserProfilePhoto> profilePhotos;
  final String? about;

  UserModel({
    required this.id,
    required this.username,
    required this.tag,
    this.profilePictureUrl,
    this.profilePhotos = const [],
    this.about,
  });

  String get displayHandle => '$username#$tag';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String,
      tag: json['tag'] as String? ?? '0000',
      profilePictureUrl: json['profilePictureUrl'] as String?,
      about: json['about'] as String?,
      profilePhotos: (json['profilePhotos'] as List<dynamic>? ?? const [])
          .map((value) => UserProfilePhoto.fromJson(
                value as Map<String, dynamic>,
              ))
          .toList(growable: false),
    );
  }

  UserModel copyWith({
    int? id,
    String? username,
    String? tag,
    String? profilePictureUrl,
    bool clearProfilePicture = false,
    List<UserProfilePhoto>? profilePhotos,
    String? about,
    bool clearAbout = false,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      tag: tag ?? this.tag,
      profilePictureUrl: clearProfilePicture
          ? null
          : profilePictureUrl ?? this.profilePictureUrl,
      profilePhotos: profilePhotos ?? this.profilePhotos,
      about: clearAbout ? null : about ?? this.about,
    );
  }
}
