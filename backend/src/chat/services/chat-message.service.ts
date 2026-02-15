import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { MessagesService } from '../../messages/messages.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { FriendsService } from '../../friends/friends.service';
import { UsersService } from '../../users/users.service';
import { validateDto } from '../utils/dto.validator';
import { SendMessageDto, GetMessagesDto, ClearChatHistoryDto } from '../dto/chat.dto';
import { SendPingDto } from '../dto/send-ping.dto';
import { MessageType, MessageDeliveryStatus } from '../../messages/message.entity';

@Injectable()
export class ChatMessageService {
  private readonly logger = new Logger(ChatMessageService.name);

  constructor(
    private readonly messagesService: MessagesService,
    private readonly conversationsService: ConversationsService,
    private readonly friendsService: FriendsService,
    private readonly usersService: UsersService,
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
      data.content,
      sender,
      conversation,
      {
        expiresAt,
        messageType: data.messageType,
        mediaUrl: data.mediaUrl,
        mediaDuration: data.mediaDuration,
      },
    );

    const messagePayload = {
      id: message.id,
      content: message.content,
      senderId: sender.id,
      senderEmail: sender.email,
      senderUsername: sender.username,
      conversationId: conversation.id,
      createdAt: message.createdAt,
      deliveryStatus: message.deliveryStatus,
      expiresAt: message.expiresAt
        ? new Date(message.expiresAt).toISOString()
        : null,
      messageType: message.messageType,
      mediaUrl: message.mediaUrl,
      mediaDuration: message.mediaDuration,
      tempId: data.tempId, // Return tempId for optimistic message matching
    };

    // Emit to sender (confirmation)
    client.emit('messageSent', messagePayload);

    // Emit to recipient if online
    const recipientSocketId = onlineUsers.get(data.recipientId);
    if (recipientSocketId) {
      server.to(recipientSocketId).emit('newMessage', messagePayload);
    }
  }

  async handleGetMessages(client: Socket, data: any) {
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

      const mapped = active.map((m) => ({
        id: m.id,
        content: m.content,
        senderId: m.sender.id,
        senderEmail: m.sender.email,
        senderUsername: m.sender.username,
        conversationId: data.conversationId,
        createdAt: m.createdAt,
        deliveryStatus: m.deliveryStatus || 'SENT',
        expiresAt: m.expiresAt
          ? new Date(m.expiresAt as any).toISOString()
          : null,
        messageType: m.messageType || 'TEXT',
        mediaUrl: m.mediaUrl,
      }));

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

    const payload = {
      id: message.id,
      content: '',
      senderId: user.id,
      senderEmail: user.email,
      senderUsername: user.username,
      conversationId: conversation.id,
      createdAt: message.createdAt,
      messageType: MessageType.PING,
      deliveryStatus: message.deliveryStatus,
      expiresAt: message.expiresAt
        ? new Date(message.expiresAt).toISOString()
        : null,
      mediaUrl: null,
    };

    client.emit('pingSent', payload);

    const recipientSocketId = onlineUsers.get(recipientId);
    if (recipientSocketId) {
      server.to(recipientSocketId).emit('newPing', payload);
    }
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

    const readerId = user.id;
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
}
