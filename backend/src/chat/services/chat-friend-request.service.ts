import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { FriendsService } from '../../friends/friends.service';
import { BlockedService } from '../../blocked/blocked.service';
import { UsersService } from '../../users/users.service';
import { User } from '../../users/user.entity';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { MediaCleanupService } from '../../media/media-cleanup.service';
import { validateDto } from '../utils/dto.validator';
import {
  SendFriendRequestDto,
  AcceptFriendRequestDto,
  RejectFriendRequestDto,
  UnfriendDto,
} from '../dto/chat.dto';
import { FriendRequestMapper } from '../mappers/friend-request.mapper';
import { UserMapper } from '../mappers/user.mapper';
import { FriendRequestStatus } from '../../friends/friend-request.entity';
import { ChatConversationService } from './chat-conversation.service';

@Injectable()
export class ChatFriendRequestService {
  private readonly logger = new Logger(ChatFriendRequestService.name);

  constructor(
    private readonly friendsService: FriendsService,
    private readonly blockedService: BlockedService,
    private readonly usersService: UsersService,
    private readonly conversationsService: ConversationsService,
    private readonly messagesService: MessagesService,
    private readonly mediaCleanup: MediaCleanupService,
    private readonly chatConversationService: ChatConversationService,
  ) {}

  /** Emit friendsList to client and optionally to another socket. */
  private async emitFriendsListToBoth(
    client: Socket,
    server: Server,
    clientUserId: number,
    otherSocketId: string | undefined,
    otherUserId: number | undefined,
  ): Promise<void> {
    try {
      const clientFriends = await this.friendsService.getFriends(clientUserId);
      client.emit('friendsList', clientFriends.map((u) => UserMapper.toPayload(u)));
      if (otherSocketId != null && otherUserId != null) {
        const otherFriends = await this.friendsService.getFriends(otherUserId);
        server.to(otherSocketId).emit('friendsList', otherFriends.map((u) => UserMapper.toPayload(u)));
      }
    } catch (error) {
      this.logger.error('emitFriendsListToBoth (non-critical):', error);
    }
  }

  /** Emit conversationsList to client and optionally to another socket.
   *  Uses the same unread-count + blocked-user filtering as handleGetConversations. */
  private async emitConversationsListToBoth(
    client: Socket,
    server: Server,
    clientUserId: number,
    otherSocketId: string | undefined,
    otherUserId: number | undefined,
  ): Promise<void> {
    try {
      const clientList = await this._buildConversationsList(clientUserId);
      client.emit('conversationsList', clientList);
      if (otherSocketId != null && otherUserId != null) {
        const otherList = await this._buildConversationsList(otherUserId);
        server.to(otherSocketId).emit('conversationsList', otherList);
      }
    } catch (error) {
      this.logger.error('emitConversationsListToBoth (non-critical):', error);
    }
  }

  /** Build the conversation list payload for a user, including unread counts and blocked-user filtering. */
  private async _buildConversationsList(userId: number): Promise<any[]> {
    const [rawConvs, blockedIds, blockedByUserIds] = await Promise.all([
      this.conversationsService.findByUser(userId),
      this.blockedService.getBlockedUserIds(userId),
      this.blockedService.getBlockedByUserIds(userId),
    ]);
    const excludeSet = new Set([...blockedIds, ...blockedByUserIds]);
    const filtered = rawConvs.filter((conv) => {
      const otherId = conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
      return !excludeSet.has(otherId);
    });
    return this.chatConversationService.conversationsWithUnread(filtered, userId);
  }

  /** Emit pendingRequestsCount to client and optionally to another socket. */
  private async emitPendingCountToBoth(
    client: Socket,
    server: Server,
    clientUserId: number,
    otherSocketId: string | undefined,
    otherUserId: number | undefined,
  ): Promise<void> {
    try {
      const clientCount = await this.friendsService.getPendingRequestCount(clientUserId);
      client.emit('pendingRequestsCount', { count: clientCount });
      if (otherSocketId != null && otherUserId != null) {
        const otherCount = await this.friendsService.getPendingRequestCount(otherUserId);
        server.to(otherSocketId).emit('pendingRequestsCount', { count: otherCount });
      }
    } catch (error) {
      this.logger.error('emitPendingCountToBoth (non-critical):', error);
    }
  }

  /** Emit full auto-accept flow: friendRequestAccepted, friendsList, conversation + lists, openConversation, pendingCount. */
  private async emitAutoAcceptFlow(
    client: Socket,
    server: Server,
    sender: User,
    recipient: User,
    payload: any,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const recipientSocketId = onlineUsers.get(recipient.id);
    try {
      client.emit('friendRequestAccepted', payload);
      if (recipientSocketId) server.to(recipientSocketId).emit('friendRequestAccepted', payload);
    } catch (error) {
      this.logger.error('emitAutoAcceptFlow: friendRequestAccepted (non-critical):', error);
    }
    await this.emitFriendsListToBoth(client, server, sender.id, recipientSocketId, recipient.id);
    let conversation: any = null;
    try {
      conversation = await this.conversationsService.findOrCreate(sender, recipient);
      this.logger.debug(`Auto-accept: conversation created/found id=${conversation.id}`);
    } catch (error) {
      this.logger.error('emitAutoAcceptFlow: findOrCreate (non-critical):', error);
    }
    await this.emitConversationsListToBoth(client, server, sender.id, recipientSocketId, recipient.id);
    if (conversation) client.emit('openConversation', { conversationId: conversation.id });
    await this.emitPendingCountToBoth(client, server, sender.id, recipientSocketId, recipient.id);
  }

  async handleSendFriendRequest(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const senderId: number = client.data.user?.id;
    if (!senderId) return;

    try {
      const dto = validateDto(SendFriendRequestDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const sender = await this.usersService.findById(senderId);
    const recipient = await this.usersService.findById(data.recipientId);

    if (!sender || !recipient) {
      client.emit('error', { message: 'User not found' });
      return;
    }
    if (recipient.id === senderId) {
      client.emit('error', { message: 'Cannot send friend request to yourself' });
      return;
    }

    // If recipient has blocked sender, do not allow the request
    const recipientBlockedSender = await this.blockedService.isBlocked(
      recipient.id,
      sender.id,
    );
    if (recipientBlockedSender) {
      client.emit('error', { message: 'You are blocked by this user' });
      return;
    }

    // Step 2: Send friend request (CRITICAL - if this fails, entire operation fails)
    let friendRequest: any;
    let payload: any;
    try {
      this.logger.debug(
        `sendFriendRequest: sender=${sender.username} (id=${sender.id}), recipient=${recipient.username} (id=${recipient.id})`,
      );
      friendRequest = await this.friendsService.sendRequest(sender, recipient);
      this.logger.debug(
        `sendFriendRequest: created request id=${friendRequest.id}, status=${friendRequest.status}`,
      );

      payload = FriendRequestMapper.toPayload(friendRequest);
    } catch (error) {
      this.logger.error(`sendFriendRequest: Failed to send request:`, error);
      client.emit('error', {
        message: error.message || 'Failed to send friend request',
      });
      return; // Critical failure - stop here
    }

    // Check if it was auto-accepted (mutual request scenario)
    if (friendRequest.status === FriendRequestStatus.ACCEPTED) {
      this.logger.debug(`Auto-accept: ${sender.username} <-> ${recipient.username}`);
      await this.emitAutoAcceptFlow(client, server, sender, recipient, payload, onlineUsers);
    } else {
      // Normal pending request flow
      // Step 4a: Notify sender (important but not critical)
      try {
        this.logger.debug(
          `sendFriendRequest: emitting friendRequestSent to sender ${sender.username}`,
        );
        client.emit('friendRequestSent', payload);
      } catch (error) {
        this.logger.error(
          'sendFriendRequest: Failed to emit friendRequestSent (non-critical):',
          error,
        );
      }

      // Step 4b: Notify recipient if online (non-critical)
      try {
        const recipientSocketId = onlineUsers.get(recipient.id);
        this.logger.debug(
          `sendFriendRequest: recipient ${recipient.username} (id=${recipient.id}) socketId=${recipientSocketId || 'OFFLINE'}`,
        );
        if (recipientSocketId) {
          server.to(recipientSocketId).emit('newFriendRequest', payload);
          const count = await this.friendsService.getPendingRequestCount(
            recipient.id,
          );
          server.to(recipientSocketId).emit('pendingRequestsCount', { count });
          this.logger.debug(
            `sendFriendRequest: emitted newFriendRequest + pendingRequestsCount(${count}) to recipient`,
          );
        }
      } catch (error) {
        this.logger.error(
          'sendFriendRequest: Failed to notify recipient (non-critical):',
          error,
        );
      }
    }
  }

  async handleAcceptFriendRequest(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(AcceptFriendRequestDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    // Step 1: Accept the friend request (CRITICAL - if this fails, entire operation fails)
    let friendRequest: any;
    let senderSocketId: string | undefined;
    try {
      this.logger.debug(
        `acceptFriendRequest: requestId=${data.requestId}, userId=${userId}`,
      );
      friendRequest = await this.friendsService.acceptRequest(
        data.requestId,
        userId,
      );
      this.logger.debug(
        `acceptFriendRequest: accepted, sender=${friendRequest.sender.id} (${friendRequest.sender.username}), receiver=${friendRequest.receiver.id} (${friendRequest.receiver.username})`,
      );

      const payload = FriendRequestMapper.toPayload(friendRequest);

      // Notify both users
      client.emit('friendRequestAccepted', payload);

      senderSocketId = onlineUsers.get(friendRequest.sender.id);
      if (senderSocketId) {
        server.to(senderSocketId).emit('friendRequestAccepted', payload);
      }
    } catch (error) {
      this.logger.error(
        'acceptFriendRequest: Failed to accept request:',
        error,
      );
      client.emit('error', {
        message: error.message || 'Failed to accept friend request',
      });
      return; // Critical failure - stop here
    }

    // Step 2: Create conversation (important but not critical - partial success possible)
    let conversation: any = null;
    try {
      const senderUser = await this.usersService.findById(
        friendRequest.sender.id,
      );
      const receiverUser = await this.usersService.findById(
        friendRequest.receiver.id,
      );
      if (senderUser && receiverUser) {
        conversation = await this.conversationsService.findOrCreate(
          senderUser,
          receiverUser,
        );
        this.logger.debug(
          `acceptFriendRequest: conversation id=${conversation.id}`,
        );
      }
    } catch (error) {
      this.logger.error(
        'acceptFriendRequest: Failed to create conversation (non-critical):',
        error,
      );
      // Continue - users are friends even if conversation creation failed
    }

    // Step 3: Refresh conversations list (non-critical)
    await this.emitConversationsListToBoth(
      client,
      server,
      userId,
      senderSocketId,
      friendRequest.sender.id,
    );

    // Step 4: Update friend requests list and pending count (non-critical)
    try {
      const pendingRequests = await this.friendsService.getPendingRequests(userId);
      client.emit('friendRequestsList', pendingRequests.map(FriendRequestMapper.toPayload));
      const pendingCount = await this.friendsService.getPendingRequestCount(userId);
      client.emit('pendingRequestsCount', { count: pendingCount });
    } catch (error) {
      this.logger.error('acceptFriendRequest: friend requests list (non-critical):', error);
    }

    // Step 5: Emit updated friends lists (non-critical)
    await this.emitFriendsListToBoth(
      client,
      server,
      userId,
      senderSocketId,
      friendRequest.sender.id,
    );

    // Step 6: Emit openConversation only to caller (acceptor) — sender should not auto-open chat
    if (conversation) {
      this.logger.debug(`acceptFriendRequest: emitting openConversation id=${conversation.id} to acceptor only`);
      client.emit('openConversation', { conversationId: conversation.id });
    }
  }

  async handleRejectFriendRequest(client: Socket, data: any) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(RejectFriendRequestDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const friendRequest = await this.friendsService.rejectRequest(
      data.requestId,
      userId,
    );

    const payload = FriendRequestMapper.toPayload(friendRequest);
    client.emit('friendRequestRejected', payload);

    const pendingRequests =
      await this.friendsService.getPendingRequests(userId);
    client.emit(
      'friendRequestsList',
      pendingRequests.map(FriendRequestMapper.toPayload),
    );

    const pendingCount =
      await this.friendsService.getPendingRequestCount(userId);
    client.emit('pendingRequestsCount', { count: pendingCount });
  }

  async handleGetFriendRequests(client: Socket) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    const friendRequests = await this.friendsService.getPendingRequests(userId);
    client.emit(
      'friendRequestsList',
      friendRequests.map(FriendRequestMapper.toPayload),
    );

    const count = await this.friendsService.getPendingRequestCount(userId);
    client.emit('pendingRequestsCount', { count });
  }

  async handleGetFriends(client: Socket) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    const [friends, blockedIds, blockedByUserIds] = await Promise.all([
      this.friendsService.getFriends(userId),
      this.blockedService.getBlockedUserIds(userId),
      this.blockedService.getBlockedByUserIds(userId),
    ]);
    const excludeSet = new Set([...blockedIds, ...blockedByUserIds]);
    const filtered = friends.filter((u) => !excludeSet.has(u.id));
    const list = filtered.map((u) => UserMapper.toPayload(u));
    client.emit('friendsList', list);
  }

  async handleUnfriend(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const currentUserId: number = client.data.user?.id;
    if (!currentUserId) return;

    try {
      const dto = validateDto(UnfriendDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    this.logger.debug(
      `handleUnfriend: currentUserId=${currentUserId}, targetUserId=${data.userId}`,
    );

    // Step 1: Delete the friend relationship (CRITICAL - if this fails, operation fails)
    try {
      await this.friendsService.unfriend(currentUserId, data.userId);
    } catch (error) {
      this.logger.error('handleUnfriend: Failed to unfriend:', error);
      client.emit('error', {
        message: error.message || 'Failed to unfriend user',
      });
      return; // Critical failure - stop here
    }

    // Step 2: Delete the conversation (important but not critical)
    try {
      const conversation = await this.conversationsService.findByUsers(
        currentUserId,
        data.userId,
      );
      if (conversation) {
        const mediaUrls = await this.messagesService.findMediaUrlsByConversation(
          conversation.id,
        );
        await Promise.all(
          mediaUrls.map((url) => this.mediaCleanup.deleteMediaFile(url)),
        );
        await this.conversationsService.delete(conversation.id);
        this.logger.debug(
          `handleUnfriend: deleted conversation id=${conversation.id}`,
        );
      }
    } catch (error) {
      this.logger.error(
        'handleUnfriend: Failed to delete conversation (non-critical):',
        error,
      );
      // Continue - users are unfriended even if conversation deletion failed
    }

    const otherUserSocketId = onlineUsers.get(data.userId);

    // Step 3: Notify both users (non-critical)
    try {
      client.emit('unfriended', { userId: currentUserId });
      if (otherUserSocketId) {
        server.to(otherUserSocketId).emit('unfriended', { userId: currentUserId });
      }
    } catch (error) {
      this.logger.error('handleUnfriend: emit unfriended (non-critical):', error);
    }

    // Step 4 & 5: Refresh conversations and friends lists for both users (non-critical)
    await this.emitConversationsListToBoth(
      client,
      server,
      currentUserId,
      otherUserSocketId,
      data.userId,
    );
    await this.emitFriendsListToBoth(
      client,
      server,
      currentUserId,
      otherUserSocketId,
      data.userId,
    );
  }
}
