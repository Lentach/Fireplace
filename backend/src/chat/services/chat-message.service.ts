import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { MessagesService } from '../../messages/messages.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { FriendsService } from '../../friends/friends.service';
import { BlockedService } from '../../blocked/blocked.service';
import { UsersService } from '../../users/users.service';
import { LinkPreviewService } from './link-preview.service';
import { PushNotificationsService } from '../../push-notifications/push-notifications.service';
import { validateDto } from '../utils/dto.validator';
import { SendMessageDto, GetMessagesDto, ClearChatHistoryDto, DeleteMessageDto, AddReactionDto, RemoveReactionDto } from '../dto/chat.dto';
import { SendPingDto } from '../dto/send-ping.dto';
import { MessageType, MessageDeliveryStatus } from '../../messages/message.entity';
import { MessageMapper } from '../../messages/message.mapper';

@Injectable()
export class ChatMessageService {
  private readonly logger = new Logger(ChatMessageService.name);

  constructor(
    private readonly messagesService: MessagesService,
    private readonly conversationsService: ConversationsService,
    private readonly friendsService: FriendsService,
    private readonly blockedService: BlockedService,
    private readonly usersService: UsersService,
    private readonly linkPreviewService: LinkPreviewService,
    private readonly pushNotificationsService: PushNotificationsService,
  ) {}

  async handleSendMessage(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const senderId: number = client.data.user?.id;
    if (!senderId) return;

    try {
      const dto = validateDto(SendMessageDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const blocked = await this.blockedService.isBlockedByEither(
      senderId,
      data.recipientId,
    );
    if (blocked) {
      client.emit('error', {
        message: 'Cannot message this user',
      });
      return;
    }
    const areFriends = await this.friendsService.areFriends(
      senderId,
      data.recipientId,
    );
    if (!areFriends) {
      client.emit('error', {
        message: 'You can only message friends',
      });
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

    const expiresAt = data.expiresIn
      ? new Date(Date.now() + data.expiresIn * 1000)
      : null;

    const message = await this.messagesService.create(
      data.encryptedContent ? '[encrypted]' : data.content,
      sender,
      conversation,
      {
        expiresAt,
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

    // Emit to recipient if online via WebSocket
    const recipientSocketId = onlineUsers.get(data.recipientId);
    if (recipientSocketId) {
      server.to(recipientSocketId).emit('newMessage', messagePayload);
    }

    // Always send push — when browser is minimized WebSocket stays connected but
    // user won't see the message; FCM delivers to Service Worker which shows system notification.
    // When app is foreground FCM delivers to onMessage, no duplicate notification shown.
    this.pushNotificationsService.notify(data.recipientId).catch(() => {});

    // Async link preview — fire and forget, does not block send
    // Skip for encrypted messages (server cannot read content)
    if (!data.encryptedContent && message.messageType === MessageType.TEXT && data.content) {
      this.linkPreviewService.fetchPreview(data.content).then(async (preview) => {
        if (!preview) return;
        const updated = await this.messagesService.updateLinkPreview(
          message.id,
          preview.url,
          preview.title,
          preview.imageUrl,
        );
        if (!updated) return;
        const previewPayload = {
          messageId: message.id,
          conversationId: conversation.id,
          linkPreviewUrl: preview.url,
          linkPreviewTitle: preview.title,
          linkPreviewImageUrl: preview.imageUrl,
        };
        client.emit('linkPreviewReady', previewPayload);
        if (recipientSocketId) {
          server.to(recipientSocketId).emit('linkPreviewReady', previewPayload);
        }
      }).catch(() => { /* swallow — preview is best-effort */ });
    }
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

    try {
      const messages = await this.messagesService.findByConversation(
        data.conversationId,
        data.limit,
        data.offset,
        userId,
      );

      // Filter out expired messages (cron cleans DB every minute, but messages
      // may still be in DB between cron runs).
      // Use getTime() because TypeORM may return expiresAt as string or Date
      // depending on pg driver — direct comparison (string > Date) yields NaN.
      const nowMs = Date.now();

      // Debug: log raw message data for disappearing messages diagnostics
      const withExpiry = messages.filter((m) => m.expiresAt);
      if (withExpiry.length > 0) {
        this.logger.debug(
          `[getMessages] conv=${data.conversationId}: ${messages.length} total, ` +
          `${withExpiry.length} with expiresAt. now=${new Date(nowMs).toISOString()}`,
        );
        for (const m of withExpiry) {
          const raw = m.expiresAt;
          const parsed = new Date(raw as any).getTime();
          const diff = parsed - nowMs;
          this.logger.debug(
            `  msg#${m.id}: expiresAt raw=${raw} (type=${typeof raw}), ` +
            `parsed=${parsed}, diff=${diff}ms, keep=${!isNaN(parsed) && parsed > nowMs}`,
          );
        }
      }

      const active = messages.filter(
        (m) => !m.expiresAt || new Date(m.expiresAt as any).getTime() > nowMs,
      );

      if (withExpiry.length > 0) {
        this.logger.debug(
          `[getMessages] After filter: ${active.length} active (was ${messages.length})`,
        );
      }

      const mapped = active.map((m) =>
        MessageMapper.toPayload(m, { conversationId: data.conversationId }),
      );

      client.emit('messageHistory', mapped);
    } catch (error) {
      this.logger.error(
        `Failed to get messages for conversation ${data.conversationId}: ${error.message}`,
        error.stack,
      );
      client.emit('messageHistory', []);
    }
  }

  async handleSendPing(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const user = client.data.user;
    if (!user) return;

    try {
      const dto = validateDto(SendPingDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const { recipientId } = data;

    const blocked = await this.blockedService.isBlockedByEither(
      user.id,
      recipientId,
    );
    if (blocked) {
      client.emit('error', { message: 'Cannot message this user' });
      return;
    }
    // Check if friends
    const areFriends = await this.friendsService.areFriends(
      user.id,
      recipientId,
    );
    if (!areFriends) {
      client.emit('error', { message: 'You can only ping friends' });
      return;
    }

    // Get sender and recipient User entities
    const sender = await this.usersService.findById(user.id);
    const recipient = await this.usersService.findById(recipientId);
    if (!sender || !recipient) {
      client.emit('error', { message: 'User not found' });
      return;
    }

    // Find or create conversation
    const conversation = await this.conversationsService.findOrCreate(
      sender,
      recipient,
    );

    // Use conversation's disappearing timer for ping expiration
    const expiresAt = conversation.disappearingTimer
      ? new Date(Date.now() + conversation.disappearingTimer * 1000)
      : null;

    // Create ping message
    const message = await this.messagesService.create(
      '', // Empty content for ping
      sender,
      conversation,
      {
        messageType: MessageType.PING,
        expiresAt,
      },
    );

    const payload = MessageMapper.toPayload(message, {
      conversationId: conversation.id,
    });

    client.emit('pingSent', payload);

    const recipientSocketId = onlineUsers.get(recipientId);
    if (recipientSocketId) {
      server.to(recipientSocketId).emit('newPing', payload);
    }
    this.pushNotificationsService.notify(recipientId).catch(() => {});
  }

  async handleMessageDelivered(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const user = client.data.user;
    if (!user) return;

    const { messageId } = data;
    if (!messageId) {
      client.emit('error', { message: 'messageId is required' });
      return;
    }

    const updated = await this.messagesService.updateDeliveryStatus(
      messageId,
      MessageDeliveryStatus.DELIVERED,
    );

    if (!updated) return;

    // Emit actual status (READ if markConversationRead was processed first)
    const senderSocketId = onlineUsers.get(updated.sender.id);
    if (senderSocketId) {
      server.to(senderSocketId).emit('messageDelivered', {
        messageId: updated.id,
        conversationId: updated.conversation?.id,
        deliveryStatus: updated.deliveryStatus,
      });
    }
  }

  async handleMarkConversationRead(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const user = client.data.user;
    if (!user) return;

    const conversationId = data?.conversationId;
    if (conversationId == null) {
      client.emit('error', { message: 'conversationId is required' });
      return;
    }

    const conversation = await this.conversationsService.findById(
      Number(conversationId),
    );
    if (!conversation) return;

    // Verify the caller is a member of this conversation
    const readerId = user.id;
    if (conversation.userOne.id !== readerId && conversation.userTwo.id !== readerId) {
      this.logger.warn(`handleMarkConversationRead: user ${readerId} is not a member of conv ${conversationId}`);
      return;
    }

    const otherUserId =
      conversation.userOne.id === readerId
        ? conversation.userTwo.id
        : conversation.userOne.id;

    const updated = await this.messagesService.markConversationAsReadFromSender(
      Number(conversationId),
      otherUserId,
    );

    for (const message of updated) {
      const senderSocketId = onlineUsers.get(message.sender.id);
      if (senderSocketId) {
        server.to(senderSocketId).emit('messageDelivered', {
          messageId: message.id,
          conversationId: Number(conversationId),
          deliveryStatus: MessageDeliveryStatus.READ,
        });
      }
    }
  }

  async handleClearChatHistory(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
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
      conversation.userOne.id === userId ||
      conversation.userTwo.id === userId;
    if (!userBelongs) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    // Delete all messages
    await this.messagesService.deleteAllByConversation(data.conversationId);

    // Emit to both users
    const otherUserId =
      conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;

    const payload = { conversationId: data.conversationId };

    // Emit to initiating user
    client.emit('chatHistoryCleared', payload);

    // Emit to other user if online
    const otherUserSocketId = onlineUsers.get(otherUserId);
    if (otherUserSocketId) {
      server.to(otherUserSocketId).emit('chatHistoryCleared', payload);
    }

    this.logger.debug(
      `User ${userId} cleared chat history for conversation ${data.conversationId}`,
    );
  }

  async handleDeleteMessage(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
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

    const message = await this.messagesService.findByIdWithConversation(messageId);
    if (!message) {
      client.emit('error', { message: 'Message not found' });
      return;
    }

    const conv = message.conversation;
    if (!conv) {
      client.emit('error', { message: 'Conversation not found' });
      return;
    }

    const userBelongs = conv.userOne.id === userId || conv.userTwo.id === userId;
    if (!userBelongs) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    const otherUserId = conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    const conversationId = conv.id;

    if (mode === 'for_me') {
      const ok = await this.messagesService.hideMessageForUser(messageId, userId);
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
      const deleted = await this.messagesService.deleteById(messageId, userId);
      if (!deleted) {
        client.emit('error', {
          message: 'Only the sender can delete for everyone',
        });
        return;
      }
      client.emit('messageDeleted', {
        messageId,
        conversationId,
        forEveryone: true,
      });
      const otherSocketId = onlineUsers.get(otherUserId);
      if (otherSocketId) {
        server.to(otherSocketId).emit('messageDeleted', {
          messageId,
          conversationId,
          forEveryone: true,
        });
      }
      this.logger.debug(`User ${userId} deleted message ${messageId} for everyone`);
    }
  }

  async handleAddReaction(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(AddReactionDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const message = await this.messagesService.findByIdWithConversation(data.messageId);
    if (!message) { client.emit('error', { message: 'Message not found' }); return; }

    const conv = message.conversation;
    if (conv.userOne.id !== userId && conv.userTwo.id !== userId) {
      client.emit('error', { message: 'Unauthorized' }); return;
    }

    const updated = await this.messagesService.addOrUpdateReaction(data.messageId, userId, data.emoji);
    if (!updated) return;

    const reactions = updated.reactions ? JSON.parse(updated.reactions) : {};
    const payload = { messageId: updated.id, conversationId: conv.id, reactions };

    client.emit('reactionUpdated', payload);
    const otherUserId = conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    const otherSocketId = onlineUsers.get(otherUserId);
    if (otherSocketId) server.to(otherSocketId).emit('reactionUpdated', payload);
  }

  async handleRemoveReaction(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(RemoveReactionDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const message = await this.messagesService.findByIdWithConversation(data.messageId);
    if (!message) { client.emit('error', { message: 'Message not found' }); return; }

    const conv = message.conversation;
    if (conv.userOne.id !== userId && conv.userTwo.id !== userId) {
      client.emit('error', { message: 'Unauthorized' }); return;
    }

    const updated = await this.messagesService.removeReaction(data.messageId, userId, data.emoji);
    if (!updated) return;

    const reactions = updated.reactions ? JSON.parse(updated.reactions) : {};
    const payload = { messageId: updated.id, conversationId: conv.id, reactions };

    client.emit('reactionUpdated', payload);
    const otherUserId = conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    const otherSocketId = onlineUsers.get(otherUserId);
    if (otherSocketId) server.to(otherSocketId).emit('reactionUpdated', payload);
  }
}
