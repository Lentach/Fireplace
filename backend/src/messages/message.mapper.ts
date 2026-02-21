import { Message } from './message.entity';

export class MessageMapper {
  static toPayload(
    message: Message,
    options?: { tempId?: string; conversationId?: number },
  ) {
    const sender = message.sender;
    const convId =
      options?.conversationId ?? message.conversation?.id ?? null;
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
      tempId: options?.tempId ?? null,
      reactions: message.reactions ? JSON.parse(message.reactions) : {},
      encryptedContent: message.encryptedContent ?? null,
      linkPreviewUrl: message.linkPreviewUrl ?? null,
      linkPreviewTitle: message.linkPreviewTitle ?? null,
      linkPreviewImageUrl: message.linkPreviewImageUrl ?? null,
    };

    if (message.replyTo) {
      const rt = message.replyTo;
      const contentPreview =
        rt.content && rt.messageType === 'TEXT'
          ? rt.content.substring(0, 150)
          : rt.messageType === 'VOICE'
            ? 'Voice message'
            : rt.messageType === 'IMAGE' || rt.messageType === 'DRAWING'
              ? 'Image'
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
