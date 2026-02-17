import { Message } from './message.entity';

export class MessageMapper {
  static toPayload(
    message: Message,
    options?: { tempId?: string; conversationId?: number },
  ) {
    const sender = message.sender;
    const convId =
      options?.conversationId ?? message.conversation?.id ?? null;
    return {
      id: message.id,
      content: message.content,
      senderId: sender?.id,
      senderEmail: sender?.email,
      senderUsername: sender?.username ?? null,
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
    };
  }
}
