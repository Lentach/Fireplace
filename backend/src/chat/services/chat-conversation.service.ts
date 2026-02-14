import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { UsersService } from '../../users/users.service';
import { FriendsService } from '../../friends/friends.service';
import { validateDto } from '../utils/dto.validator';
import {
  StartConversationDto,
  DeleteConversationDto,
  SetDisappearingTimerDto,
} from '../dto/chat.dto';
import { ConversationMapper } from '../mappers/conversation.mapper';
import { UserMapper } from '../mappers/user.mapper';

@Injectable()
export class ChatConversationService {
  private readonly logger = new Logger(ChatConversationService.name);

  constructor(
    private readonly conversationsService: ConversationsService,
    private readonly messagesService: MessagesService,
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
    const list = await this._conversationsWithUnread(conversations, userId);
    client.emit('conversationsList', list);

    client.emit('openConversation', { conversationId: conversation.id });
  }

  private async _conversationsWithUnread(
    conversations: any[],
    userId: number,
  ): Promise<any[]> {
    const result: any[] = [];
    for (const conv of conversations) {
      const unreadCount = await this.messagesService.countUnreadForRecipient(
        conv.id,
        userId,
      );
      const lastMessage = await this.messagesService.getLastMessage(conv.id);
      result.push(
        ConversationMapper.toPayload(conv, { unreadCount, lastMessage }),
      );
    }
    return result;
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

    const list = await this._conversationsWithUnread(conversations, userId);
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
    const list = await this._conversationsWithUnread(conversations, userId);
    client.emit('conversationsList', list);

    if (otherUserSocketId) {
      const otherConversations =
        await this.conversationsService.findByUser(otherUserId);
      const otherList = await this._conversationsWithUnread(
        otherConversations,
        otherUserId,
      );
      server.to(otherUserSocketId).emit('conversationsList', otherList);
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

  async handleSetDisappearingTimer(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(SetDisappearingTimerDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const conversation = await this.conversationsService.findById(
      data.conversationId,
    );
    if (!conversation) {
      client.emit('error', { message: 'Conversation not found' });
      return;
    }

    // Verify user belongs to this conversation
    const userBelongs =
      conversation.userOne.id === userId || conversation.userTwo.id === userId;
    if (!userBelongs) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    // Update timer
    await this.conversationsService.updateDisappearingTimer(
      data.conversationId,
      data.seconds,
    );

    // Get other user ID
    const otherUserId =
      conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;

    const payload = {
      conversationId: data.conversationId,
      seconds: data.seconds,
    };

    // Emit to both users
    client.emit('disappearingTimerUpdated', payload);

    const otherUserSocketId = onlineUsers.get(otherUserId);
    if (otherUserSocketId) {
      server.to(otherUserSocketId).emit('disappearingTimerUpdated', payload);
    }

    this.logger.debug(
      `User ${userId} set disappearing timer to ${data.seconds}s for conversation ${data.conversationId}`,
    );
  }
}
