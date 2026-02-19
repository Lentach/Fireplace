import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { UsersService } from '../../users/users.service';
import { FriendsService } from '../../friends/friends.service';
import { validateDto } from '../utils/dto.validator';
import {
  StartConversationDto,
  SetDisappearingTimerDto,
  DeleteConversationOnlyDto,
} from '../dto/chat.dto';
import { ConversationMapper } from '../mappers/conversation.mapper';

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
    const otherUser = await this.usersService.findById(data.recipientId);

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
      const lastMessage = await this.messagesService.getLastMessage(
        conv.id,
        userId,
      );
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
      `handleGetConversations: userId=${userId}, username=${client.data.user?.username}`,
    );
    const conversations = await this.conversationsService.findByUser(userId);
    this.logger.debug(
      `handleGetConversations: found ${conversations.length} conversations for userId=${userId}`,
    );

    const list = await this._conversationsWithUnread(conversations, userId);
    client.emit('conversationsList', list);
  }

  async handleDeleteConversationOnly(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId = client.data.user?.id;
    if (!userId) return;

    // 1. Validate DTO
    let dto: DeleteConversationOnlyDto;
    try {
      dto = validateDto(DeleteConversationOnlyDto, data);
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    // 2. Find conversation
    const conversation = await this.conversationsService.findById(
      dto.conversationId,
    );
    if (!conversation) {
      client.emit('error', { message: 'Conversation not found' });
      return;
    }

    // 3. Verify user belongs to conversation
    const userBelongs =
      conversation.userOne.id === userId || conversation.userTwo.id === userId;
    if (!userBelongs) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    // 4. Get other user ID
    const otherUserId =
      conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;

    // 5. Delete messages + conversation (wrap in try-catch)
    try {
      await this.messagesService.deleteAllByConversation(dto.conversationId);
      await this.conversationsService.delete(dto.conversationId);
    } catch (error) {
      this.logger.error('Failed to delete conversation:', error);
      client.emit('error', { message: 'Failed to delete conversation' });
      return;
    }

    // 6. Emit to both users
    const payload = { conversationId: dto.conversationId };
    client.emit('conversationDeleted', payload);

    const otherSocketId = onlineUsers.get(otherUserId);
    if (otherSocketId) {
      server.to(otherSocketId).emit('conversationDeleted', payload);
    }

    // 7. Refresh conversations list for both users
    const userConvs = await this.conversationsService.findByUser(userId);
    const userList = await this._conversationsWithUnread(userConvs, userId);
    client.emit('conversationsList', userList);

    if (otherSocketId) {
      const otherConvs = await this.conversationsService.findByUser(otherUserId);
      const otherList = await this._conversationsWithUnread(
        otherConvs,
        otherUserId,
      );
      server.to(otherSocketId).emit('conversationsList', otherList);
    }

    this.logger.debug(
      `Conversation ${dto.conversationId} deleted by user ${userId}. Friend relationship preserved.`,
    );

    // NOTE: friend_request is NOT deleted - remains ACCEPTED
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
