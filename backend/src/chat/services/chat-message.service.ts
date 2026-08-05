import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { MessagesService } from '../../messages/messages.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { ChatValidationService } from './chat-validation.service';
import { UsersService } from '../../users/users.service';
import { ChatLinkPreviewService } from './chat-link-preview.service';
import { PushNotificationCoalescingService } from '../../push-notifications/push-notification-coalescing.service';
import { validateDto } from '../utils/dto.validator';
import {
  SendMessageDto,
  GetMessagesDto,
  ClearChatHistoryDto,
  DeleteMessageDto,
  GetServedMessageIdsDto,
} from '../dto/chat.dto';
import { MessageDeliveredDto } from '../dto/message-delivered.dto';
import { MarkConversationReadDto } from '../dto/mark-conversation-read.dto';
import { MessageDeliveryStatus } from '../../messages/message.entity';
import { MessageMapper } from '../../messages/message.mapper';
import { MediaCleanupService } from '../../media/media-cleanup.service';
import { isMessageExpired } from '../../messages/message-expiry.util';
import { EditMessageDto } from '../dto/edit-message.dto';
import {
  emitToNewestTab,
  newestSocketForUser,
  userRoom,
} from '../utils/user-room';

/** Editing a sent message is only allowed within this window after it was created. */
const EDIT_WINDOW_MS = 15 * 60 * 1000;

/**
 * The socket's authenticated user id, or null before auth completed.
 *
 * `client.data` is `any` in socket.io's types; the gateway writes `data.user`
 * itself at auth time, so this narrows an INTERNAL shape rather than external
 * input. Runtime-narrowed instead of cast so the lint ratchet stays honest —
 * used by the served-ids handler; older handlers keep their historical
 * pattern untouched.
 */
function servedIdsCallerId(client: Socket): number | null {
  const data: unknown = client.data;
  if (!data || typeof data !== 'object' || !('user' in data)) return null;
  const user = data.user;
  if (!user || typeof user !== 'object' || !('id' in user)) return null;
  return typeof user.id === 'number' ? user.id : null;
}

@Injectable()
export class ChatMessageService {
  private readonly logger = new Logger(ChatMessageService.name);

  constructor(
    private readonly messagesService: MessagesService,
    private readonly conversationsService: ConversationsService,
    private readonly chatValidationService: ChatValidationService,
    private readonly usersService: UsersService,
    private readonly chatLinkPreviewService: ChatLinkPreviewService,
    private readonly pushCoalescingService: PushNotificationCoalescingService,
    private readonly mediaCleanup: MediaCleanupService,
  ) {}

  async handleSendMessage(client: Socket, data: any, server: Server) {
    const senderId: number = client.data.user?.id;
    if (!senderId) return;

    try {
      const dto = validateDto(SendMessageDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const validation = await this.chatValidationService.validateCanMessage(
      senderId,
      data.recipientId,
    );
    if (!validation.valid) {
      client.emit('error', { message: validation.error });
      return;
    }

    const sender = await this.usersService.findById(senderId);
    const recipient = await this.usersService.findById(data.recipientId);
    if (!sender || !recipient) {
      client.emit('error', { message: 'User not found' });
      return;
    }

    const conversation = await this.conversationsService.findOrCreate(
      sender,
      recipient,
    );

    const ttlSeconds: number | null =
      data.expiresIn ?? conversation.disappearingTimer ?? null;
    const disappearAfterSeconds =
      ttlSeconds != null && ttlSeconds > 0 ? ttlSeconds : null;

    const message = await this.messagesService.create(
      data.encryptedContent ? '[encrypted]' : data.content,
      sender,
      conversation,
      {
        expiresAt: null,
        disappearAfterSeconds,
        messageType: data.messageType,
        mediaUrl: data.mediaUrl,
        mediaDuration: data.mediaDuration,
        replyToMessageId: data.replyToMessageId ?? null,
        encryptedContent: data.encryptedContent ?? null,
      },
    );

    const messagePayload = MessageMapper.toPayload(message, {
      tempId: data.tempId,
      conversationId: conversation.id,
    });

    // Emit to sender (confirmation)
    client.emit('messageSent', messagePayload);

    // CIPHERTEXT — one tab only, deliberately NOT room-addressed (BE-007).
    // Signal decryption consumes the message key and advances the ratchet, and
    // the client's tabs share one session store, so fanning this out would make
    // the second tab's decrypt of the same ciphertext FAIL into its decryption
    // failure policy. `emitToNewestTab` reproduces the previous last-write-wins
    // behaviour exactly. See `utils/user-room.ts`.
    const delivered = emitToNewestTab(
      server,
      data.recipientId,
      'newMessage',
      messagePayload,
    );
    this.logger.debug(
      delivered
        ? `[sendMessage] newMessage emitted to recipient ${data.recipientId}`
        : `[sendMessage] Recipient ${data.recipientId} NOT ONLINE - newMessage not emitted`,
    );

    // Coalesced push: minimized tabs stay connected via WS but still need a wake-up;
    // skip scheduling when recipient reports foreground + same active conversation.
    if (
      !this.shouldSkipPushForFocusedRecipient(
        server,
        data.recipientId,
        conversation.id,
      )
    ) {
      this.pushCoalescingService
        .scheduleMessagePush(data.recipientId, conversation.id, sender.username)
        .catch(() => {});
    }

    // Async link preview — fire and forget, does not block send
    this.chatLinkPreviewService.fetchAndEmitIfNeeded({
      content: data.content,
      encryptedContent: data.encryptedContent ?? null,
      messageType: message.messageType,
      messageId: message.id,
      conversationId: conversation.id,
      client,
      recipientId: data.recipientId,
      server,
    });
  }

  async handleGetMessages(client: Socket, data: any) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(GetMessagesDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    // H-01: enforce conversation membership before serving history. Without this
    // any authenticated user could read any (sequential-id) conversation's
    // messages. Mirrors the membership check in handleMarkConversationRead.
    const conversation = await this.conversationsService.findById(
      data.conversationId,
    );
    if (
      !conversation ||
      (conversation.userOne.id !== userId && conversation.userTwo.id !== userId)
    ) {
      client.emit('messageHistory', {
        conversationId: data.conversationId,
        messages: [],
      });
      return;
    }

    try {
      const messages = await this.messagesService.findByConversation(
        data.conversationId,
        data.limit,
        data.offset,
        userId,
      );

      const now = new Date();
      const active = messages.filter((m) => !isMessageExpired(m, now));

      const mapped = active.map((m) =>
        MessageMapper.toPayload(m, { conversationId: data.conversationId }),
      );

      client.emit('messageHistory', {
        conversationId: data.conversationId,
        messages: mapped,
      });
    } catch (error) {
      this.logger.error(
        `Failed to get messages for conversation ${data.conversationId}: ${error.message}`,
        error.stack,
      );
      client.emit('messageHistory', {
        conversationId: data.conversationId,
        messages: [],
      });
    }
  }

  /**
   * Answer "which of these message ids do you still serve me?".
   *
   * The client destroys the local plaintext of every id it asked about that is
   * MISSING from the reply — that is how a message deleted or expired before
   * the device learned about it finally leaves the disk. Two consequences:
   *
   *  - An empty `messageIds` is a legitimate answer (a fully cleared history)
   *    and is read as "destroy all of them". It must therefore never be
   *    manufactured by a failure. Unlike `handleGetMessages`, which answers a
   *    database error with an empty history, this handler answers it with
   *    SILENCE: no reply leaves the client holding everything until next time.
   *  - `requestId` is echoed verbatim so a late or foreign reply cannot be
   *    applied to the wrong batch.
   */
  async handleGetServedMessageIds(client: Socket, data: unknown) {
    const userId = servedIdsCallerId(client);
    if (!userId) return;

    let dto: GetServedMessageIdsDto;
    try {
      dto = validateDto(GetServedMessageIdsDto, data);
    } catch (error) {
      client.emit('error', {
        message: error instanceof Error ? error.message : String(error),
      });
      return;
    }

    try {
      const messageIds = await this.messagesService.findServedMessageIds(
        dto.messageIds,
        userId,
      );
      client.emit('servedMessageIds', {
        requestId: dto.requestId,
        messageIds,
      });
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.logger.error(
        `Failed to resolve served message ids for user ${userId}: ${err.message}`,
        err.stack,
      );
      // No reply on purpose — see above.
    }
  }

  async handleMessageDelivered(client: Socket, data: any, server: Server) {
    const user = client.data.user;
    if (!user) return;
    const userId: number = user.id;

    let messageId: number;
    try {
      const dto = validateDto(MessageDeliveredDto, data);
      messageId = dto.messageId;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    // Verify caller is the recipient of this message
    const message =
      await this.messagesService.findByIdWithConversation(messageId);
    if (!message) return;

    const conv = message.conversation as any;
    const recipientId =
      conv.userOne?.id === message.sender.id
        ? conv.userTwo?.id
        : conv.userOne?.id;
    if (userId !== recipientId) return; // Silently ignore — not the intended recipient

    const updated = await this.messagesService.updateDeliveryStatus(
      messageId,
      MessageDeliveryStatus.DELIVERED,
    );
    if (!updated) return;

    server.to(userRoom(updated.sender.id)).emit('messageDelivered', {
      messageId: updated.id,
      conversationId: updated.conversation?.id,
      deliveryStatus: updated.deliveryStatus,
    });
  }

  async handleMarkConversationRead(client: Socket, data: any, server: Server) {
    const user = client.data.user;
    if (!user) return;

    let conversationId: number;
    try {
      const dto = validateDto(MarkConversationReadDto, data);
      conversationId = dto.conversationId;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const conversation =
      await this.conversationsService.findById(conversationId);
    if (!conversation) return;

    // Verify the caller is a member of this conversation
    const readerId = user.id;
    if (
      conversation.userOne.id !== readerId &&
      conversation.userTwo.id !== readerId
    ) {
      this.logger.warn(
        `handleMarkConversationRead: user ${readerId} is not a member of conv ${conversationId}`,
      );
      return;
    }

    const otherUserId =
      conversation.userOne.id === readerId
        ? conversation.userTwo.id
        : conversation.userOne.id;

    const updated = await this.messagesService.markConversationAsReadFromSender(
      conversationId,
      otherUserId,
    );

    for (const message of updated) {
      const payload: Record<string, unknown> = {
        messageId: message.id,
        conversationId: Number(conversationId),
        deliveryStatus: MessageDeliveryStatus.READ,
      };
      if (message.expiresAt) {
        payload.expiresAt = new Date(message.expiresAt as Date).toISOString();
      }

      server.to(userRoom(message.sender.id)).emit('messageDelivered', payload);
      // Compared by USER id, not socket id. The old socket-id comparison was
      // incidentally correct because reader and sender are always different
      // users here (you mark the OTHER party's messages read); with rooms the
      // two are distinct rooms anyway, so this guard only documents that.
      if (readerId !== message.sender.id) {
        server.to(userRoom(readerId)).emit('messageDelivered', payload);
      }
    }
  }

  async handleClearChatHistory(client: Socket, data: any, server: Server) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(ClearChatHistoryDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    // Verify user belongs to this conversation
    const conversation = await this.conversationsService.findById(
      data.conversationId,
    );
    if (!conversation) {
      client.emit('error', { message: 'Conversation not found' });
      return;
    }

    const userBelongs =
      conversation.userOne.id === userId || conversation.userTwo.id === userId;
    if (!userBelongs) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    const mediaUrls = await this.messagesService.findMediaUrlsByConversation(
      data.conversationId,
    );
    await Promise.all(
      mediaUrls.map((url) => this.mediaCleanup.deleteMediaFile(url)),
    );
    await this.messagesService.deleteAllByConversation(data.conversationId);

    // Emit to both users
    const otherUserId =
      conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;

    const payload = { conversationId: data.conversationId };

    // Emit to initiating user
    client.emit('chatHistoryCleared', payload);

    server.to(userRoom(otherUserId)).emit('chatHistoryCleared', payload);

    this.logger.debug(
      `User ${userId} cleared chat history for conversation ${data.conversationId}`,
    );
  }

  async handleDeleteMessage(client: Socket, data: any, server: Server) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(DeleteMessageDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const { messageId, mode } = data;

    const message =
      await this.messagesService.findByIdWithConversation(messageId);
    if (!message) {
      client.emit('error', { message: 'Message not found' });
      return;
    }

    const conv = message.conversation;
    if (!conv) {
      client.emit('error', { message: 'Conversation not found' });
      return;
    }

    const userBelongs =
      conv.userOne.id === userId || conv.userTwo.id === userId;
    if (!userBelongs) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    const otherUserId =
      conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    const conversationId = conv.id;

    if (mode === 'for_me') {
      const ok = await this.messagesService.hideMessageForUser(
        messageId,
        userId,
      );
      if (!ok) {
        client.emit('error', { message: 'Failed to hide message' });
        return;
      }
      client.emit('messageDeleted', {
        messageId,
        conversationId,
        forEveryone: false,
      });
      this.logger.debug(`User ${userId} hid message ${messageId} for self`);
      return;
    }

    if (mode === 'for_everyone') {
      if (message.mediaUrl) {
        await this.mediaCleanup.deleteMediaFile(message.mediaUrl);
      }
      const deleted = await this.messagesService.deleteById(messageId, userId);
      if (!deleted) {
        client.emit('error', {
          message: 'Only the sender can delete for everyone',
        });
        return;
      }
      if (conv.pinnedMessageId === messageId) {
        await this.conversationsService.clearPinnedMessage(conversationId);
        const unpinPayload = { conversationId };
        client.emit('messageUnpinned', unpinPayload);
        server.to(userRoom(otherUserId)).emit('messageUnpinned', unpinPayload);
      }
      client.emit('messageDeleted', {
        messageId,
        conversationId,
        forEveryone: true,
      });
      server.to(userRoom(otherUserId)).emit('messageDeleted', {
        messageId,
        conversationId,
        forEveryone: true,
      });
      this.logger.debug(
        `User ${userId} deleted message ${messageId} for everyone`,
      );
    }
  }

  async handleEditMessage(client: Socket, data: any, server: Server) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(EditMessageDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const { messageId } = data;

    const message =
      await this.messagesService.findByIdWithConversation(messageId);
    if (!message) {
      client.emit('editMessageFailed', { messageId, reason: 'not_found' });
      return;
    }

    const conv = message.conversation;
    if (!conv) {
      client.emit('editMessageFailed', { messageId, reason: 'not_found' });
      return;
    }

    // Membership first (mirror delete): only the two participants may touch the message.
    const userBelongs =
      conv.userOne.id === userId || conv.userTwo.id === userId;
    if (!userBelongs) {
      client.emit('editMessageFailed', { messageId, reason: 'not_sender' });
      return;
    }

    // Sender-only: only the author may edit their own message.
    if (message.sender?.id !== userId) {
      client.emit('editMessageFailed', { messageId, reason: 'not_sender' });
      return;
    }

    // 15-minute edit window.
    if (Date.now() - new Date(message.createdAt).getTime() > EDIT_WINDOW_MS) {
      client.emit('editMessageFailed', { messageId, reason: 'window_expired' });
      return;
    }

    // v1 is text-only: never let a crafted client swap a media row's ciphertext
    // (messageType is a server-visible column, so this is cheap defense-in-depth).
    if (message.messageType !== 'TEXT') {
      client.emit('editMessageFailed', { messageId, reason: 'not_text' });
      return;
    }

    const otherUserId =
      conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    const conversationId = conv.id;

    // Server stays blind: store the new ciphertext, keep content as the placeholder.
    // Expiry / deliveryStatus are intentionally left untouched.
    const updated = await this.messagesService.editMessage(messageId, userId, {
      encryptedContent: data.encryptedContent ?? null,
      content: '[encrypted]',
    });
    if (!updated || !updated.editedAt) {
      client.emit('editMessageFailed', { messageId, reason: 'not_found' });
      return;
    }

    const payload = {
      messageId,
      conversationId,
      content: '[encrypted]',
      encryptedContent: data.encryptedContent ?? null,
      editedAt: updated.editedAt.toISOString(),
    };

    client.emit('messageEdited', payload);
    // CIPHERTEXT — one tab only, same reason as newMessage (BE-007): an edit
    // carries a fresh Signal payload over the existing session, so a second
    // tab decrypting it would consume a key the first already used.
    emitToNewestTab(server, otherUserId, 'messageEdited', payload);
    this.logger.debug(`User ${userId} edited message ${messageId}`);
  }

  /**
   * When the tab that WILL RECEIVE the message reports foreground + this
   * conversation active, WS already delivers `newMessage` — no push needed.
   *
   * Deliberately evaluates the SAME socket `emitToNewestTab` delivers to, not
   * "any focused tab" (BE-007). Polling every tab would let a focused tab A
   * suppress the push while the ciphertext went to background tab B, leaving
   * the user with neither the live message nor a notification. When the
   * ciphertext carve-out is lifted this must become room-wide in the SAME
   * change, so delivery and suppression never disagree.
   */
  private shouldSkipPushForFocusedRecipient(
    server: Server,
    recipientId: number,
    conversationId: number,
  ): boolean {
    const state = newestSocketForUser(server, recipientId)?.data
      ?.pushClientState as
      | { activeConversationId?: number | null; clientVisible?: boolean }
      | undefined;
    if (!state?.clientVisible) return false;
    return state.activeConversationId === conversationId;
  }
}
