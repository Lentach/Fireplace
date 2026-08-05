import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { MessagesService } from '../../messages/messages.service';
import { LinkPreviewService } from './link-preview.service';
import { userRoom } from '../utils/user-room';

@Injectable()
export class ChatLinkPreviewService {
  private readonly logger = new Logger(ChatLinkPreviewService.name);

  constructor(
    private readonly messagesService: MessagesService,
    private readonly linkPreviewService: LinkPreviewService,
  ) {}

  /**
   * Fire-and-forget: fetch OG link preview for a text message and emit
   * `linkPreviewReady` to both sender and recipient.
   *
   * Skipped when `encryptedContent` is present (server can't read content).
   */
  fetchAndEmitIfNeeded(opts: {
    content: string | null;
    encryptedContent: string | null;
    messageType: string;
    messageId: number;
    conversationId: number;
    client: Socket;
    recipientId: number;
    server: Server;
  }): void {
    const {
      content,
      encryptedContent,
      messageType,
      messageId,
      conversationId,
      client,
      recipientId,
      server,
    } = opts;

    // Skip for encrypted messages (server cannot read content)
    if (encryptedContent) return;
    if (messageType !== 'TEXT') return;
    if (!content) return;

    this.linkPreviewService
      .fetchPreview(content)
      .then(async (preview) => {
        if (!preview) return;
        const updated = await this.messagesService.updateLinkPreview(
          messageId,
          preview.url,
          preview.title,
          preview.imageUrl,
        );
        if (!updated) return;
        const previewPayload = {
          messageId,
          conversationId,
          linkPreviewUrl: preview.url,
          linkPreviewTitle: preview.title,
          linkPreviewImageUrl: preview.imageUrl,
        };
        client.emit('linkPreviewReady', previewPayload);
        // Room-addressed so every open tab gets the card, not just the newest
        // (BE-007). Safe to fan out: the payload is plaintext OG metadata, not
        // ciphertext, so there is no ratchet state to consume.
        server
          .to(userRoom(recipientId))
          .emit('linkPreviewReady', previewPayload);
      })
      .catch(() => {
        /* swallow — preview is best-effort */
      });
  }
}
