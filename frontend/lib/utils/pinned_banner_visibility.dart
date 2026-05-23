import '../models/conversation_model.dart';
import 'message_expiry.dart';

/// Whether the pinned-message banner should render for [conv].
///
/// Uses server [ConversationModel.pinnedMessagePreview] — not local message list
/// membership. Preview is null when the pinned row is hidden (delete-for-me).
bool shouldShowPinnedMessageBanner(ConversationModel? conv) {
  if (conv == null || conv.pinnedMessageId == null) return false;
  final preview = conv.pinnedMessagePreview;
  if (preview == null) return false;
  if (isMessageExpired(preview)) return false;
  return true;
}
