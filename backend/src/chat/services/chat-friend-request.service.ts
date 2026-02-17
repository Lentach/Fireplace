import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { FriendsService } from '../../friends/friends.service';
import { UsersService } from '../../users/users.service';
import { User } from '../../users/user.entity';
import { ConversationsService } from '../../conversations/conversations.service';
import { validateDto } from '../utils/dto.validator';
import {
  SendFriendRequestDto,
  AcceptFriendRequestDto,
  RejectFriendRequestDto,
  UnfriendDto,
} from '../dto/chat.dto';
import { FriendRequestMapper } from '../mappers/friend-request.mapper';
import { UserMapper } from '../mappers/user.mapper';
import { ConversationMapper } from '../mappers/conversation.mapper';

@Injectable()
export class ChatFriendRequestService {
  private readonly logger = new Logger(ChatFriendRequestService.name);

  constructor(
    private readonly friendsService: FriendsService,
    private readonly usersService: UsersService,
    private readonly conversationsService: ConversationsService,
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

  /** Emit conversationsList to client and optionally to another socket. */
  private async emitConversationsListToBoth(
    client: Socket,
    server: Server,
    clientUserId: number,
    otherSocketId: string | undefined,
    otherUserId: number | undefined,
  ): Promise<void> {
    try {
      const clientConvs = await this.conversationsService.findByUser(clientUserId);
      client.emit('conversationsList', clientConvs.map((c) => ConversationMapper.toPayload(c)));
      if (otherSocketId != null && otherUserId != null) {
        const otherConvs = await this.conversationsService.findByUser(otherUserId);
        server.to(otherSocketId).emit('conversationsList', otherConvs.map((c) => ConversationMapper.toPayload(c)));
      }
    } catch (error) {
      this.logger.error('emitConversationsListToBoth (non-critical):', error);
    }
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

  /** Emit openConversation to client and optionally to another socket. */
  private emitOpenConversationToBoth(
    client: Socket,
    server: Server,
    conversationId: number,
    otherSocketId: string | undefined,
  ): void {
    try {
      client.emit('openConversation', { conversationId });
      if (otherSocketId) {
        server.to(otherSocketId).emit('openConversation', { conversationId });
      }
    } catch (error) {
      this.logger.error('emitOpenConversationToBoth (non-critical):', error);
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
    if (conversation) this.emitOpenConversationToBoth(client, server, conversation.id, recipientSocketId);
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

    // Step 1: Find users (CRITICAL - if either user not found, fail)
    const sender = await this.usersService.findById(senderId);
    const recipient = await this.usersService.findByEmail(data.recipientEmail);

    if (!sender || !recipient) {
      client.emit('error', { message: 'User not found' });
      return;
    }

    // Step 2: Send friend request (CRITICAL - if this fails, entire operation fails)
    let friendRequest: any;
    let payload: any;
    try {
      this.logger.debug(
        `sendFriendRequest: sender=${sender.email} (id=${sender.id}), recipient=${recipient.email} (id=${recipient.id})`,
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
    if (friendRequest.status === 'accepted') {
      this.logger.debug(`Auto-accept: ${sender.email} <-> ${recipient.email}`);
      await this.emitAutoAcceptFlow(client, server, sender, recipient, payload, onlineUsers);
    } else {
      // Normal pending request flow
      // Step 4a: Notify sender (important but not critical)
      try {
        this.logger.debug(
          `sendFriendRequest: emitting friendRequestSent to sender ${sender.email}`,
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
          `sendFriendRequest: recipient ${recipient.email} (id=${recipient.id}) socketId=${recipientSocketId || 'OFFLINE'}`,
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
        `acceptFriendRequest: accepted, sender=${friendRequest.sender.id} (${friendRequest.sender.email}), receiver=${friendRequest.receiver.id} (${friendRequest.receiver.email})`,
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

    // Step 6: Emit openConversation (non-critical)
    if (conversation) {
      this.logger.debug(`acceptFriendRequest: emitting openConversation id=${conversation.id}`);
      this.emitOpenConversationToBoth(client, server, conversation.id, senderSocketId);
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

    const friends = await this.friendsService.getFriends(userId);
    const list = friends.map((u) => UserMapper.toPayload(u));
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
