import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { FriendsService } from '../../friends/friends.service';
import { UsersService } from '../../users/users.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { validateDto } from '../utils/dto.validator';
import {
  SendFriendRequestDto,
  AcceptFriendRequestDto,
  RejectFriendRequestDto,
  UnfriendDto,
  UpdateActiveStatusDto,
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
      const recipientSocketId = onlineUsers.get(recipient.id);

      // Step 3a: Emit acceptance events (important but not critical)
      try {
        client.emit('friendRequestAccepted', payload);
        if (recipientSocketId) {
          server.to(recipientSocketId).emit('friendRequestAccepted', payload);
        }
      } catch (error) {
        this.logger.error(
          'sendFriendRequest: Failed to emit friendRequestAccepted (non-critical):',
          error,
        );
      }

      // Step 3b: Emit friends lists (non-critical)
      try {
        const senderFriends = await this.friendsService.getFriends(sender.id);
        const receiverFriends = await this.friendsService.getFriends(
          recipient.id,
        );

        client.emit('friendsList', senderFriends.map(UserMapper.toPayload));

        if (recipientSocketId) {
          server
            .to(recipientSocketId)
            .emit('friendsList', receiverFriends.map(UserMapper.toPayload));
        }
      } catch (error) {
        this.logger.error(
          'sendFriendRequest: Failed to emit friends lists (non-critical):',
          error,
        );
      }

      // Step 3c: Create conversation and refresh lists (non-critical)
      let conversation: any = null;
      try {
        conversation = await this.conversationsService.findOrCreate(
          sender,
          recipient,
        );
        this.logger.debug(
          `Auto-accept: conversation created/found id=${conversation.id}`,
        );

        const senderConversations = await this.conversationsService.findByUser(
          sender.id,
        );
        client.emit(
          'conversationsList',
          senderConversations.map(ConversationMapper.toPayload),
        );

        if (recipientSocketId) {
          const receiverConversations =
            await this.conversationsService.findByUser(recipient.id);
          server
            .to(recipientSocketId)
            .emit(
              'conversationsList',
              receiverConversations.map(ConversationMapper.toPayload),
            );
        }
      } catch (error) {
        this.logger.error(
          'sendFriendRequest: Failed to create/refresh conversations (non-critical):',
          error,
        );
      }

      // Step 3d: Emit openConversation (non-critical)
      try {
        if (conversation) {
          client.emit('openConversation', { conversationId: conversation.id });

          if (recipientSocketId) {
            server.to(recipientSocketId).emit('openConversation', {
              conversationId: conversation.id,
            });
          }
        }
      } catch (error) {
        this.logger.error(
          'sendFriendRequest: Failed to emit openConversation (non-critical):',
          error,
        );
      }

      // Step 3e: Update pending counts (non-critical)
      try {
        const senderCount = await this.friendsService.getPendingRequestCount(
          sender.id,
        );
        client.emit('pendingRequestsCount', { count: senderCount });
        if (recipientSocketId) {
          const receiverCount =
            await this.friendsService.getPendingRequestCount(recipient.id);
          server
            .to(recipientSocketId)
            .emit('pendingRequestsCount', { count: receiverCount });
        }
      } catch (error) {
        this.logger.error(
          'sendFriendRequest: Failed to update pending counts (non-critical):',
          error,
        );
      }
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
          server
            .to(recipientSocketId)
            .emit('pendingRequestsCount', { count });
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
    try {
      const senderConversations = await this.conversationsService.findByUser(
        friendRequest.sender.id,
      );

      if (senderSocketId) {
        server
          .to(senderSocketId)
          .emit(
            'conversationsList',
            senderConversations.map(ConversationMapper.toPayload),
          );
      }

      const receiverConversations = await this.conversationsService.findByUser(
        userId,
      );
      client.emit(
        'conversationsList',
        receiverConversations.map(ConversationMapper.toPayload),
      );
    } catch (error) {
      this.logger.error(
        'acceptFriendRequest: Failed to refresh conversations (non-critical):',
        error,
      );
      // Continue - user still sees friend request accepted
    }

    // Step 4: Update friend requests list and pending count (non-critical)
    try {
      const pendingRequests = await this.friendsService.getPendingRequests(
        userId,
      );
      client.emit(
        'friendRequestsList',
        pendingRequests.map(FriendRequestMapper.toPayload),
      );

      const pendingCount = await this.friendsService.getPendingRequestCount(
        userId,
      );
      client.emit('pendingRequestsCount', { count: pendingCount });
    } catch (error) {
      this.logger.error(
        'acceptFriendRequest: Failed to update friend requests list (non-critical):',
        error,
      );
      // Continue
    }

    // Step 5: Emit updated friends lists (non-critical but important)
    try {
      const senderFriends = await this.friendsService.getFriends(
        friendRequest.sender.id,
      );
      this.logger.debug(
        `acceptFriendRequest: senderFriends count=${senderFriends.length}`,
      );

      const receiverFriends = await this.friendsService.getFriends(userId);
      this.logger.debug(
        `acceptFriendRequest: receiverFriends count=${receiverFriends.length}`,
      );

      // Send to sender (if online)
      if (senderSocketId) {
        server
          .to(senderSocketId)
          .emit('friendsList', senderFriends.map(UserMapper.toPayload));
      }

      // Send to receiver (current user)
      client.emit('friendsList', receiverFriends.map(UserMapper.toPayload));
    } catch (error) {
      this.logger.error(
        'acceptFriendRequest: Failed to emit friends lists (non-critical):',
        error,
      );
      // Continue
    }

    // Step 6: Emit openConversation event (non-critical)
    try {
      if (conversation) {
        this.logger.debug(
          `acceptFriendRequest: emitting openConversation id=${conversation.id}`,
        );
        client.emit('openConversation', { conversationId: conversation.id });

        if (senderSocketId) {
          server.to(senderSocketId).emit('openConversation', {
            conversationId: conversation.id,
          });
        }
      }
    } catch (error) {
      this.logger.error(
        'acceptFriendRequest: Failed to emit openConversation (non-critical):',
        error,
      );
      // No need to continue - this is the last step
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

    const pendingRequests = await this.friendsService.getPendingRequests(
      userId,
    );
    client.emit(
      'friendRequestsList',
      pendingRequests.map(FriendRequestMapper.toPayload),
    );

    const pendingCount = await this.friendsService.getPendingRequestCount(
      userId,
    );
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
    client.emit('friendsList', friends.map(UserMapper.toPayload));
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
      const notifyPayload = { userId: currentUserId };
      client.emit('unfriended', notifyPayload);

      if (otherUserSocketId) {
        server
          .to(otherUserSocketId)
          .emit('unfriended', { userId: currentUserId });
      }
    } catch (error) {
      this.logger.error(
        'handleUnfriend: Failed to emit unfriended event (non-critical):',
        error,
      );
    }

    // Step 4: Refresh conversations for both users (non-critical)
    try {
      const conversations = await this.conversationsService.findByUser(
        currentUserId,
      );
      client.emit(
        'conversationsList',
        conversations.map(ConversationMapper.toPayload),
      );

      if (otherUserSocketId) {
        const otherConversations = await this.conversationsService.findByUser(
          data.userId,
        );
        server
          .to(otherUserSocketId)
          .emit(
            'conversationsList',
            otherConversations.map(ConversationMapper.toPayload),
          );
      }
    } catch (error) {
      this.logger.error(
        'handleUnfriend: Failed to refresh conversations (non-critical):',
        error,
      );
    }

    // Step 5: Emit updated friends lists to both users (non-critical)
    try {
      const currentUserFriends = await this.friendsService.getFriends(
        currentUserId,
      );
      client.emit(
        'friendsList',
        currentUserFriends.map(UserMapper.toPayload),
      );
      this.logger.debug(
        `handleUnfriend: emitted friendsList to currentUser, count=${currentUserFriends.length}`,
      );

      if (otherUserSocketId) {
        const otherUserFriends = await this.friendsService.getFriends(
          data.userId,
        );
        server
          .to(otherUserSocketId)
          .emit('friendsList', otherUserFriends.map(UserMapper.toPayload));
        this.logger.debug(
          `handleUnfriend: emitted friendsList to otherUser, count=${otherUserFriends.length}`,
        );
      }
    } catch (error) {
      this.logger.error(
        'handleUnfriend: Failed to emit friends lists (non-critical):',
        error,
      );
    }
  }

  async handleUpdateActiveStatus(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(UpdateActiveStatusDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    this.logger.debug(
      `handleUpdateActiveStatus: userId=${userId}, activeStatus=${data.activeStatus}`,
    );

    // Step 1: Update active status in database (CRITICAL)
    try {
      await this.usersService.updateActiveStatus(userId, data.activeStatus);
    } catch (error) {
      this.logger.error(
        'handleUpdateActiveStatus: Failed to update status:',
        error,
      );
      client.emit('error', {
        message: error.message || 'Failed to update active status',
      });
      return; // Critical failure - stop here
    }

    // Step 2: Notify all friends about the status change (non-critical)
    try {
      const friends = await this.friendsService.getFriends(userId);

      for (const friend of friends) {
        const friendSocketId = onlineUsers.get(friend.id);
        if (friendSocketId) {
          server.to(friendSocketId).emit('userStatusChanged', {
            userId,
            activeStatus: data.activeStatus,
          });
          this.logger.debug(
            `handleUpdateActiveStatus: notified friend ${friend.id} about status change`,
          );
        }
      }
    } catch (error) {
      this.logger.error(
        'handleUpdateActiveStatus: Failed to notify friends (non-critical):',
        error,
      );
      // Status was updated successfully, just couldn't notify - not critical
    }

    // Confirm to the user
    client.emit('activeStatusUpdated', { activeStatus: data.activeStatus });
  }
}
