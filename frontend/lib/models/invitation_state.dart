import 'user_model.dart';

enum InvitationAction { send, accept, decline, ensureChat }

enum InvitationActionStatus { inFlight, failed }

enum InvitationDirection { incoming, outgoing }

class InvitationOutcome {
  static const Object _unset = Object();

  final int peerUserId;
  final InvitationDirection direction;
  final UserModel peer;
  final int? requestId;
  final int? conversationId;
  final bool chatReady;
  final String? retryToken;
  final bool retrying;

  const InvitationOutcome({
    required this.peerUserId,
    required this.direction,
    required this.peer,
    required this.requestId,
    required this.conversationId,
    required this.chatReady,
    this.retryToken,
    this.retrying = false,
  });

  InvitationOutcome copyWith({
    int? peerUserId,
    InvitationDirection? direction,
    UserModel? peer,
    Object? requestId = _unset,
    Object? conversationId = _unset,
    bool? chatReady,
    Object? retryToken = _unset,
    bool? retrying,
  }) {
    return InvitationOutcome(
      peerUserId: peerUserId ?? this.peerUserId,
      direction: direction ?? this.direction,
      peer: peer ?? this.peer,
      requestId: identical(requestId, _unset) ? this.requestId : requestId as int?,
      conversationId: identical(conversationId, _unset)
          ? this.conversationId
          : conversationId as int?,
      chatReady: chatReady ?? this.chatReady,
      retryToken: identical(retryToken, _unset)
          ? this.retryToken
          : retryToken as String?,
      retrying: retrying ?? this.retrying,
    );
  }
}

class InvitationFailure {
  final InvitationAction action;
  final int? requestId;
  final int? recipientId;
  final String reason;

  const InvitationFailure({
    required this.action,
    required this.requestId,
    required this.recipientId,
    required this.reason,
  });
}

class PendingFriendAccepted {
  final String name;
  final int peerUserId;
  final int? conversationId;
  final bool chatReady;

  const PendingFriendAccepted({
    required this.name,
    required this.peerUserId,
    required this.conversationId,
    required this.chatReady,
  });
}
