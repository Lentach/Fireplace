import '../../models/message_model.dart';

/// Full-bleed image/GIF bubble content height (matches [ImageMessageContent] / [GifMessageContent]).
const kMessageMediaBubbleHeight = 220.0;

/// Whether delivery time sits inline on the right vs stacked below.
/// Text stacks only for explicit line breaks or richer message chrome.
/// Shared by [ChatMessageBubble] and [MessageContextMenuBubbleHighlight] so overlay
/// highlight height matches the anchored bubble.
bool messageBubbleUsesInlineTime({
  required MessageModel message,
  required String displayContent,
}) {
  if (message.replyTo != null || message.linkPreviewUrl != null) return false;
  switch (message.messageType) {
    case MessageType.text:
      return !displayContent.contains('\n');
    case MessageType.ping:
      return true;
    case MessageType.image:
    case MessageType.file:
      return false;
    default:
      return false;
  }
}
