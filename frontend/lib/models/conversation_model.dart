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
  final bool muted;
  final DateTime? mutedUntil;

  ConversationModel({
    required this.id,
    required this.userOne,
    required this.userTwo,
    required this.createdAt,
    this.disappearingTimer,
    this.pinnedMessageId,
    this.pinnedMessagePreview,
    this.muted = false,
    this.mutedUntil,
  });

  bool isMutedAt(DateTime now) {
    return muted && (mutedUntil == null || mutedUntil!.isAfter(now));
  }

  bool get isNotificationMuted => isMutedAt(DateTime.now());

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
      muted: json['muted'] as bool? ?? false,
      mutedUntil: json['mutedUntil'] != null
          ? DateTime.parse(json['mutedUntil'] as String)
          : null,
    );
  }

  ConversationModel copyWith({
    int? disappearingTimer,
    bool clearDisappearingTimer = false,
    int? pinnedMessageId,
    MessageModel? pinnedMessagePreview,
    bool? muted,
    DateTime? mutedUntil,
  }) {
    return ConversationModel(
      id: id,
      userOne: userOne,
      userTwo: userTwo,
      createdAt: createdAt,
      disappearingTimer: clearDisappearingTimer
          ? null
          : disappearingTimer ?? this.disappearingTimer,
      pinnedMessageId: pinnedMessageId ?? this.pinnedMessageId,
      pinnedMessagePreview: pinnedMessagePreview ?? this.pinnedMessagePreview,
      muted: muted ?? this.muted,
      mutedUntil: mutedUntil ?? this.mutedUntil,
    );
  }
}
