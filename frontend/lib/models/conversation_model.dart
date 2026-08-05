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

  /// Clear flags exist because `x ?? this.x` cannot express "set this back to
  /// null". Without them a caller has to hand-roll the full constructor, and
  /// every field it forgets is silently reset to its default — that is how
  /// `muted`/`mutedUntil` used to be dropped by the pin handlers.
  ConversationModel copyWith({
    int? disappearingTimer,
    bool clearDisappearingTimer = false,
    int? pinnedMessageId,
    bool clearPinnedMessageId = false,
    MessageModel? pinnedMessagePreview,
    bool clearPinnedMessagePreview = false,
    bool? muted,
    DateTime? mutedUntil,
    bool clearMutedUntil = false,
  }) {
    return ConversationModel(
      id: id,
      userOne: userOne,
      userTwo: userTwo,
      createdAt: createdAt,
      disappearingTimer: clearDisappearingTimer
          ? null
          : disappearingTimer ?? this.disappearingTimer,
      pinnedMessageId: clearPinnedMessageId
          ? null
          : pinnedMessageId ?? this.pinnedMessageId,
      pinnedMessagePreview: clearPinnedMessagePreview
          ? null
          : pinnedMessagePreview ?? this.pinnedMessagePreview,
      muted: muted ?? this.muted,
      mutedUntil: clearMutedUntil ? null : mutedUntil ?? this.mutedUntil,
    );
  }
}
