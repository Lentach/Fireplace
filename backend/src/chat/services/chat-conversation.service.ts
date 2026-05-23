import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { UsersService } from '../../users/users.service';
import { BlockedService } from '../../blocked/blocked.service';
import { ChatValidationService } from './chat-validation.service';
import { validateDto } from '../utils/dto.validator';
import {
  StartConversationDto,
  SetDisappearingTimerDto,
  DeleteConversationOnlyDto,
} from '../dto/chat.dto';
import { PinMessageDto, UnpinMessageDto } from '../dto/pin-message.dto';
import { ConversationMapper } from '../mappers/conversation.mapper';
import { MediaCleanupService } from '../../media/media-cleanup.service';
import { MessageMapper } from '../../messages/message.mapper';
import { isMessageExpired } from '../../messages/message-expiry.util';

@Injectable()
export class ChatConversationService {
  private readonly logger = new Logger(ChatConversationService.name);

  constructor(
    private readonly conversationsService: ConversationsService,
    private readonly messagesService: MessagesService,
    private readonly usersService: UsersService,
    private readonly blockedService: BlockedService,
    private readonly chatValidationService: ChatValidationService,
    private readonly mediaCleanup: MediaCleanupService,
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

    const validation = await this.chatValidationService.validateCanMessage(
      userId,
      data.recipientId,
    );
    if (!validation.valid) {
      client.emit('error', { message: validation.error });
      return;
    }

    const conversation = await this.conversationsService.findOrCreate(
      user,
      otherUser,
    );

    const [rawConversations, blockedIds, blockedByUserIds] = await Promise.all([
      this.conversationsService.findByUser(userId),
      this.blockedService.getBlockedUserIds(userId),
      this.blockedService.getBlockedByUserIds(userId),
    ]);
    const excludeSet = new Set([...blockedIds, ...blockedByUserIds]);
    const conversations = rawConversations.filter((conv) => {
      const otherId =
        conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
      return !excludeSet.has(otherId);
    });
    const list = await this.conversationsWithUnread(conversations, userId);
    client.emit('conversationsList', list);
    client.emit('openConversation', { conversationId: conversation.id });

    // Emit only conversationsList to the other user (no openConversation — B should not auto-open chat)
    const otherSocketId = onlineUsers.get(data.recipientId);
    if (otherSocketId) {
      const [rawOtherConvs, otherBlockedIds, otherBlockedByUserIds] =
        await Promise.all([
          this.conversationsService.findByUser(data.recipientId),
          this.blockedService.getBlockedUserIds(data.recipientId),
          this.blockedService.getBlockedByUserIds(data.recipientId),
        ]);
      const otherExcludeSet = new Set([
        ...otherBlockedIds,
        ...otherBlockedByUserIds,
      ]);
      const otherConvs = rawOtherConvs.filter((conv) => {
        const otherId =
          conv.userOne.id === data.recipientId
            ? conv.userTwo.id
            : conv.userOne.id;
        return !otherExcludeSet.has(otherId);
      });
      const otherList = await this.conversationsWithUnread(
        otherConvs,
        data.recipientId,
      );
      server.to(otherSocketId).emit('conversationsList', otherList);
    }
  }

  async conversationsWithUnread(
    conversations: any[],
    userId: number,
  ): Promise<any[]> {
    if (conversations.length === 0) return [];

    const convIds = conversations
      .map((c) => Number(c.id))
      .filter((id) => !Number.isNaN(id));
    const [unreadMap, lastMsgMap, pinnedMsgMap] = await Promise.all([
      this.messagesService.countUnreadForRecipientBatch(convIds, userId),
      this.messagesService.getLastMessagesBatch(convIds, userId),
      this.messagesService.getPinnedMessagesBatch(
        conversations.map((c) => ({
          conversationId: Number(c.id),
          pinnedMessageId: c.pinnedMessageId ?? null,
        })),
        userId,
      ),
    ]);

    const results = conversations.map((conv) => {
      const convId = Number(conv.id);
      return ConversationMapper.toPayload(conv, {
        unreadCount: unreadMap.get(convId) ?? 0,
        lastMessage: lastMsgMap.get(convId) ?? null,
        pinnedMessage: pinnedMsgMap.get(convId) ?? null,
      });
    });

    results.sort((a, b) => {
      const aLm = a.lastMessage as { createdAt: string | Date } | null;
      const bLm = b.lastMessage as { createdAt: string | Date } | null;
      const aTime = aLm?.createdAt
        ? new Date(aLm.createdAt).getTime()
        : new Date(a.createdAt as Date | string).getTime();
      const bTime = bLm?.createdAt
        ? new Date(bLm.createdAt).getTime()
        : new Date(b.createdAt as Date | string).getTime();
      return bTime - aTime;
    });

    return results;
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
    const [rawConversations, blockedIds, blockedByUserIds] = await Promise.all([
      this.conversationsService.findByUser(userId),
      this.blockedService.getBlockedUserIds(userId),
      this.blockedService.getBlockedByUserIds(userId),
    ]);
    const excludeSet = new Set([...blockedIds, ...blockedByUserIds]);
    const conversations = rawConversations.filter((conv) => {
      const otherId =
        conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
      return !excludeSet.has(otherId);
    });
    this.logger.debug(
      `handleGetConversations: found ${conversations.length} conversations for userId=${userId}`,
    );

    const list = await this.conversationsWithUnread(conversations, userId);
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
      const mediaUrls = await this.messagesService.findMediaUrlsByConversation(
        dto.conversationId,
      );
      await Promise.all(
        mediaUrls.map((url) => this.mediaCleanup.deleteMediaFile(url)),
      );
      await this.messagesService.deleteAllByConversation(dto.conversationId);
      await this.conversationsService.delete(dto.conversationId);
    } catch (error) {
      this.logger.error('Failed to delete conversation:', error);
      client.emit('error', { message: 'Failed to delete conversation' });
      return;
    }

    // 6. Emit conversationDeleted only to caller — B gets updated list only (no auto-close)
    const payload = { conversationId: dto.conversationId };
    client.emit('conversationDeleted', payload);

    const otherSocketId = onlineUsers.get(otherUserId);

    // 7. Refresh conversations list for both users
    const userConvs = await this.conversationsService.findByUser(userId);
    const userList = await this.conversationsWithUnread(userConvs, userId);
    client.emit('conversationsList', userList);

    if (otherSocketId) {
      const otherConvs = await this.conversationsService.findByUser(otherUserId);
      const otherList = await this.conversationsWithUnread(
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

  async handlePinMessage(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    let dto: PinMessageDto;
    try {
      dto = validateDto(PinMessageDto, data);
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const conversation = await this.conversationsService.findById(
      dto.conversationId,
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

    const message = await this.messagesService.findByIdWithConversation(
      dto.messageId,
    );
    if (!message || message.conversation.id !== dto.conversationId) {
      client.emit('error', { message: 'Message not in conversation' });
      return;
    }
    if (isMessageExpired(message, new Date())) {
      client.emit('error', { message: 'Cannot pin expired message' });
      return;
    }

    const conv = await this.conversationsService.setPinnedMessage(
      dto.conversationId,
      dto.messageId,
      userId,
    );
    const snapshot = MessageMapper.toPayload(message, {
      conversationId: dto.conversationId,
    });
    const payload = {
      conversationId: dto.conversationId,
      pinnedMessageId: dto.messageId,
      pinnedMessage: snapshot,
      pinnedByUserId: userId,
      pinnedAt: conv.pinnedAt,
    };
    client.emit('messagePinned', payload);

    const otherUserId =
      conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;
    const otherUserSocketId = onlineUsers.get(otherUserId);
    if (otherUserSocketId) {
      server.to(otherUserSocketId).emit('messagePinned', payload);
    }

    this.logger.debug(
      `User ${userId} pinned message ${dto.messageId} in conversation ${dto.conversationId}`,
    );
  }

  async handleUnpinMessage(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    let dto: UnpinMessageDto;
    try {
      dto = validateDto(UnpinMessageDto, data);
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const conversation = await this.conversationsService.findById(
      dto.conversationId,
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

    await this.conversationsService.clearPinnedMessage(dto.conversationId);
    const payload = { conversationId: dto.conversationId };
    client.emit('messageUnpinned', payload);

    const otherUserId =
      conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;
    const otherUserSocketId = onlineUsers.get(otherUserId);
    if (otherUserSocketId) {
      server.to(otherUserSocketId).emit('messageUnpinned', payload);
    }

    this.logger.debug(
      `User ${userId} unpinned conversation ${dto.conversationId}`,
    );
  }
}
