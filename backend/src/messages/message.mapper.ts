import { Message } from './message.entity';
import { parseReactions } from './message-reactions.util';

export class MessageMapper {
  static toPayload(
    message: Message,
    options?: { tempId?: string; conversationId?: number },
  ) {
    const sender = message.sender;
    const convId = options?.conversationId ?? message.conversation?.id ?? null;
    const payload: Record<string, unknown> = {
      id: message.id,
      content: message.content,
      senderId: sender?.id,
      senderUsername: sender?.username,
      conversationId: convId,
      createdAt: message.createdAt,
      deliveryStatus: message.deliveryStatus || 'SENT',
      messageType: message.messageType || 'TEXT',
      mediaUrl: message.mediaUrl ?? null,
      mediaDuration: message.mediaDuration ?? null,
      expiresAt: message.expiresAt
        ? new Date(message.expiresAt as Date).toISOString()
        : null,
      disappearAfterSeconds: message.disappearAfterSeconds ?? null,
      editedAt: message.editedAt
        ? new Date(message.editedAt as Date).toISOString()
        : null,
      tempId: options?.tempId ?? null,
      reactions: parseReactions(message.reactions),
      encryptedContent: message.encryptedContent ?? null,
      linkPreviewUrl: message.linkPreviewUrl ?? null,
      linkPreviewTitle: message.linkPreviewTitle ?? null,
      linkPreviewImageUrl: message.linkPreviewImageUrl ?? null,
    };

    if (message.replyTo) {
      const rt = message.replyTo;
      payload.replyToMessageId = rt.id;
      // E2E: never expose plaintext in reply preview — use placeholder for encrypted
      const contentPreview =
        rt.encryptedContent != null
          ? 'Encrypted message'
          : rt.content && rt.messageType === 'TEXT'
            ? rt.content.substring(0, 150)
            : rt.messageType === 'VOICE'
              ? 'Voice message'
              : rt.messageType === 'IMAGE'
                ? 'Image'
                : rt.messageType === 'GIF'
                  ? 'GIF'
                  : rt.messageType === 'FILE'
                    ? 'File'
                    : rt.messageType === 'VIDEO'
                      ? 'Video'
                      : rt.messageType === 'PING'
                        ? 'Ping'
                        : '';
      payload.replyTo = {
        id: rt.id,
        content: contentPreview,
        senderUsername: rt.sender?.username ?? '',
        messageType: rt.messageType,
      };
    }

    return payload;
  }
}
