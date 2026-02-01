import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { ConversationsService } from '../../conversations/conversations.service';
import { UsersService } from '../../users/users.service';
import { FriendsService } from '../../friends/friends.service';
import { validateDto } from '../utils/dto.validator';
import { StartConversationDto, DeleteConversationDto } from '../dto/chat.dto';
import { ConversationMapper } from '../mappers/conversation.mapper';
import { UserMapper } from '../mappers/user.mapper';

@Injectable()
export class ChatConversationService {
  private readonly logger = new Logger(ChatConversationService.name);

  constructor(
    private readonly conversationsService: ConversationsService,
    private readonly usersService: UsersService,
    private readonly friendsService: FriendsService,
  ) {}

  async handleStartConversation(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(StartConversationDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const user = await this.usersService.findById(userId);
    const otherUser = await this.usersService.findByEmail(data.recipientEmail);

    if (!user || !otherUser) {
      client.emit('error', { message: 'User not found' });
      return;
    }

    const conversation = await this.conversationsService.findOrCreate(
      user,
      otherUser,
    );

    const conversations = await this.conversationsService.findByUser(userId);
    client.emit(
      'conversationsList',
      conversations.map((c) => ConversationMapper.toPayload(c as any)),
    );

    client.emit('openConversation', { conversationId: conversation.id });
  }

  async handleGetConversations(client: Socket) {
    const userId: number = client.data.user?.id;
    if (!userId) {
      this.logger.warn('handleGetConversations: no userId in client.data');
      return;
    }

    this.logger.debug(
      `handleGetConversations: userId=${userId}, email=${client.data.user?.email}`,
    );
    const conversations = await this.conversationsService.findByUser(userId);
    this.logger.debug(
      `handleGetConversations: found ${conversations.length} conversations for userId=${userId}`,
    );

    const list = conversations.map((conv) =>
      ConversationMapper.toPayload(conv as any),
    );
    client.emit('conversationsList', list);
  }

  async handleDeleteConversation(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(DeleteConversationDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    this.logger.debug(
      `deleteConversation: userId=${userId}, conversationId=${data.conversationId}`,
    );

    const conversation = await this.conversationsService.findById(
      data.conversationId,
    );
    if (!conversation) {
      client.emit('error', { message: 'Conversation not found' });
      return;
    }

    const otherUserId =
      conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;

    this.logger.debug(
      `deleteConversation: userId=${userId}, otherUserId=${otherUserId}, conversationId=${data.conversationId}`,
    );

    try {
      await this.friendsService.unfriend(userId, otherUserId);
    } catch (error) {
      this.logger.error('deleteConversation: unfriend failed:', error);
      client.emit('error', { message: error.message });
      return;
    }

    const otherUserSocketId = onlineUsers.get(otherUserId);
    if (otherUserSocketId) {
      server.to(otherUserSocketId).emit('unfriended', { userId });
    }

    await this.conversationsService.delete(data.conversationId);

    const conversations = await this.conversationsService.findByUser(userId);
    client.emit(
      'conversationsList',
      conversations.map((c) => ConversationMapper.toPayload(c as any)),
    );

    if (otherUserSocketId) {
      const otherConversations =
        await this.conversationsService.findByUser(otherUserId);
      server.to(otherUserSocketId).emit(
        'conversationsList',
        otherConversations.map((c) => ConversationMapper.toPayload(c as any)),
      );
    }

    const friends = await this.friendsService.getFriends(userId);
    client.emit(
      'friendsList',
      friends.map((u) => UserMapper.toPayload(u)),
    );

    if (otherUserSocketId) {
      const otherFriends = await this.friendsService.getFriends(otherUserId);
      server.to(otherUserSocketId).emit(
        'friendsList',
        otherFriends.map((u) => UserMapper.toPayload(u)),
      );
    }
  }
}
