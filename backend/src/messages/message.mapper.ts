import { Message, MessageType } from './message.entity';
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
      /**
       * Which of the sender's devices produced this (Phase 1, spec §5.4).
       * Null on pre-migration rows and legacy-client sends. Self-sync scoping
       * needs it — "is this mine?" becomes "is this MY DEVICE's?" — so it
       * travels with every message rather than only on the sender's ack.
       */
      originDeviceId: message.originDeviceId ?? null,
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
          : rt.content && rt.messageType === MessageType.TEXT
            ? rt.content.substring(0, 150)
            : rt.messageType === MessageType.VOICE
              ? 'Voice message'
              : rt.messageType === MessageType.IMAGE
                ? 'Image'
                : rt.messageType === MessageType.GIF
                  ? 'GIF'
                  : rt.messageType === MessageType.FILE
                    ? 'File'
                    : rt.messageType === MessageType.VIDEO
                      ? 'Video'
                      : rt.messageType === MessageType.PING
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
