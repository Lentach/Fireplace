import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { MessagesService } from '../../messages/messages.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { FriendsService } from '../../friends/friends.service';
import { UsersService } from '../../users/users.service';
import { validateDto } from '../utils/dto.validator';
import { SendMessageDto, GetMessagesDto } from '../dto/chat.dto';
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
      expiresAt: message.expiresAt,
      messageType: message.messageType,
      mediaUrl: message.mediaUrl,
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

    const messages = await this.messagesService.findByConversation(
      data.conversationId,
      data.limit,
      data.offset,
    );

    const mapped = messages.map((m) => ({
      id: m.id,
      content: m.content,
      senderId: m.sender.id,
      senderEmail: m.sender.email,
      senderUsername: m.sender.username,
      conversationId: data.conversationId,
      createdAt: m.createdAt,
      deliveryStatus: m.deliveryStatus || 'SENT',
      expiresAt: m.expiresAt,
      messageType: m.messageType || 'TEXT',
      mediaUrl: m.mediaUrl,
    }));

    client.emit('messageHistory', mapped);
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

    // Create ping message
    const message = await this.messagesService.create(
      '', // Empty content for ping
      sender,
      conversation,
      {
        messageType: MessageType.PING,
        expiresAt: null, // Pings don't expire
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
      expiresAt: null,
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

    // Update message delivery status
    const updated = await this.messagesService.updateDeliveryStatus(
      messageId,
      MessageDeliveryStatus.DELIVERED,
    );

    if (!updated) {
      return; // Message not found or already updated
    }

    // Notify the sender that their message was delivered
    const senderSocketId = onlineUsers.get(updated.sender.id);
    if (senderSocketId) {
      server.to(senderSocketId).emit('messageDelivered', {
        messageId: updated.id,
        deliveryStatus: MessageDeliveryStatus.DELIVERED,
      });
    }
  }
}
