import '../models/conversation_model.dart';
import '../models/user_model.dart';

/// Pure helpers for "other user" in a conversation. Used by [ChatProvider] and screens.

int getOtherUserId(ConversationModel conv, int? currentUserId) {
  if (currentUserId == null) return 0;
  return conv.userOne.id == currentUserId ? conv.userTwo.id : conv.userOne.id;
}

UserModel? getOtherUser(ConversationModel conv, int? currentUserId) {
  if (currentUserId == null) return null;
  return conv.userOne.id == currentUserId ? conv.userTwo : conv.userOne;
}

String getOtherUserUsername(ConversationModel conv, int? currentUserId) {
  if (currentUserId == null) return '';
  final other = getOtherUser(conv, currentUserId);
  return other?.username ?? '';
}
