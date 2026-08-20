import { Message, MessageType } from './message.entity';
import { parseReactions } from './message-reactions.util';

export class MessageMapper {
  static toPayload(
    message: Message,
    options?: {
      tempId?: string;
      conversationId?: number;
      /**
       * The ciphertext THIS device may read (spec §5.3): its own envelope, or
       * the legacy column when this device is the row's session owner. Rides
       * the existing `encryptedContent` wire field so older clients are
       * untouched.
       */
      deviceCiphertext?: string | null;
      /**
       * Why there is no ciphertext for this device (spec §12 amendment (viii)).
       * `none_for_device`: the row predates this device's link — render the
       * honest placeholder, never `[Decryption failed]`. `own_origin`: this
       * device SENT the row, so no envelope exists for it by design and the
       * plaintext lives locally. Absent whenever a ciphertext is served.
       */
      envelopeStatus?: 'none_for_device' | 'own_origin';
      /**
       * Echo the row's `sendToken` (spec §12 amendment (ix)). Only ever set
       * for the row's ORIGIN device: it is that device's lost-ack reconcile
       * key, and a new-model row carries no ciphertext for it to match on.
       */
      includeSendToken?: boolean;
    },
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
      encryptedContent: options?.envelopeStatus
        ? null
        : (options?.deviceCiphertext ?? message.encryptedContent ?? null),
      linkPreviewUrl: message.linkPreviewUrl ?? null,
      linkPreviewTitle: message.linkPreviewTitle ?? null,
      linkPreviewImageUrl: message.linkPreviewImageUrl ?? null,
    };

    if (options?.envelopeStatus) {
      payload.envelopeStatus = options.envelopeStatus;
    }
    if (options?.includeSendToken && message.sendToken) {
      payload.sendToken = message.sendToken;
    }

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
