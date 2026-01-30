import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayConnection,
  OnGatewayDisconnect,
  ConnectedSocket,
  MessageBody,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtService } from '@nestjs/jwt';
import { Logger } from '@nestjs/common';
import { UsersService } from '../users/users.service';
import { ConversationsService } from '../conversations/conversations.service';
import { MessagesService } from '../messages/messages.service';
import { FriendsService } from '../friends/friends.service';
import { validateDto } from './utils/dto.validator';
import {
  SendMessageDto,
  SendFriendRequestDto,
  AcceptFriendRequestDto,
  RejectFriendRequestDto,
  DeleteConversationDto,
  GetMessagesDto,
  StartConversationDto,
  UnfriendDto,
} from './dto/chat.dto';
import { UserMapper } from './mappers/user.mapper';
import { ConversationMapper } from './mappers/conversation.mapper';
import { FriendRequestMapper } from './mappers/friend-request.mapper';

// cors: configured from environment or default to localhost for development
@WebSocketGateway({
  cors: {
    origin: (process.env.ALLOWED_ORIGINS || 'http://localhost:3000').split(',').map(o => o.trim()),
  },
})
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(ChatGateway.name);

  @WebSocketServer()
  server: Server;

  // Map: userId -> socketId, to track who is online
  private onlineUsers = new Map<number, string>();

  constructor(
    private jwtService: JwtService,
    private usersService: UsersService,
    private conversationsService: ConversationsService,
    private messagesService: MessagesService,
    private friendsService: FriendsService,
  ) {}

  // On WebSocket connection — verify the JWT token.
  // Client sends token in query: ?token=xxx
  // Simplified: in production use middleware or handshake headers.
  async handleConnection(client: Socket) {
    try {
      const token =
        (client.handshake.query.token as string) ||
        client.handshake.auth?.token;

      if (!token) {
        client.disconnect();
        return;
      }

      const payload = this.jwtService.verify(token);
      const user = await this.usersService.findById(payload.sub);

      if (!user) {
        client.disconnect();
        return;
      }

      // Store user data in the socket object
      client.data.user = { id: user.id, email: user.email, username: user.username };
      this.onlineUsers.set(user.id, client.id);

      this.logger.debug(`User connected: ${user.email} (socket: ${client.id})`);
    } catch {
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    if (client.data.user) {
      this.onlineUsers.delete(client.data.user.id);
      this.logger.debug(`User disconnected: ${client.data.user.email}`);
    }
  }

  // Client sends: { recipientId: number, content: string }
  // Server:
  //   1. Validates message data
  //   2. Finds or creates a conversation
  //   3. Saves the message to the database
  //   4. Sends the message to the recipient (if online)
  //   5. Confirms to the sender
  @SubscribeMessage('sendMessage')
  async handleMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    const senderId: number = client.data.user?.id;
    if (!senderId) return;

    let dto: SendMessageDto;
    try {
      dto = validateDto(SendMessageDto, data);
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const sender = await this.usersService.findById(senderId);
    const recipient = await this.usersService.findById(dto.recipientId);

    if (!sender || !recipient) {
      client.emit('error', { message: 'User not found' });
      return;
    }

    // Check if users are friends
    const areFriends = await this.friendsService.areFriends(senderId, data.recipientId);
    if (!areFriends) {
      client.emit('error', { message: 'You must be friends to send messages' });
      return;
    }

    // Find or create a conversation between these two users
    const conversation = await this.conversationsService.findOrCreate(
      sender,
      recipient,
    );

    // Save the message to PostgreSQL
    const message = await this.messagesService.create(
      data.content,
      sender,
      conversation,
    );

    const messagePayload = {
      id: message.id,
      content: message.content,
      senderId: sender.id,
      senderEmail: sender.email,
      senderUsername: sender.username,
      conversationId: conversation.id,
      createdAt: message.createdAt,
    };

    // Send to recipient if they are online
    const recipientSocketId = this.onlineUsers.get(recipient.id);
    if (recipientSocketId) {
      this.server.to(recipientSocketId).emit('newMessage', messagePayload);
    }

    // Confirmation to the sender
    client.emit('messageSent', messagePayload);
  }

  // Start a conversation by email — frontend sends the other user's email
  @SubscribeMessage('startConversation')
  async handleStartConversation(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    const senderId: number = client.data.user?.id;
    if (!senderId) {
      return;
    }

    try {
      const dto = validateDto(StartConversationDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    this.logger.debug('startConversation: validated email:', data.recipientEmail);

    const sender = await this.usersService.findById(senderId);
    const recipient = await this.usersService.findByEmail(data.recipientEmail);
    this.logger.debug('startConversation: sender=', sender?.email, 'recipient=', recipient?.email, 'recipientEmail=', data.recipientEmail);

    if (!sender || !recipient) {
      this.logger.debug('startConversation: user not found, emitting error');
      client.emit('error', { message: 'User not found' });
      return;
    }

    if (sender.id === recipient.id) {
      client.emit('error', { message: 'Cannot chat with yourself' });
      return;
    }

    // Check if users are friends
    const areFriends = await this.friendsService.areFriends(sender.id, recipient.id);
    if (!areFriends) {
      client.emit('error', { message: 'You must be friends to start a conversation' });
      return;
    }

    const conversation = await this.conversationsService.findOrCreate(
      sender,
      recipient,
    );

    // Refresh the conversation list for the sender
    const conversations = await this.conversationsService.findByUser(senderId);
    const mapped = conversations.map((c) => ({
      id: c.id,
      userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
      userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
      createdAt: c.createdAt,
    }));
    client.emit('conversationsList', mapped);

    // Automatically open the new conversation
    client.emit('openConversation', { conversationId: conversation.id });
  }

  // Get message history for a conversation
  @SubscribeMessage('getMessages')
  async handleGetMessages(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    try {
      const dto = validateDto(GetMessagesDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const messages = await this.messagesService.findByConversation(
      data.conversationId,
    );

    const mapped = messages.map((m) => ({
      id: m.id,
      content: m.content,
      senderId: m.sender.id,
      senderEmail: m.sender.email,
      senderUsername: m.sender.username,
      conversationId: data.conversationId,
      createdAt: m.createdAt,
    }));

    client.emit('messageHistory', mapped);
  }

  // Get the user's conversation list
  @SubscribeMessage('getConversations')
  async handleGetConversations(@ConnectedSocket() client: Socket) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    const conversations =
      await this.conversationsService.findByUser(userId);

    client.emit('conversationsList', ConversationMapper.toPayloadArray(conversations));
  }

  // Delete a conversation (hard delete for both users)
  // IMPORTANT: This also deletes the friend relationship to prevent "Already friends" bug
  @SubscribeMessage('deleteConversation')
  async handleDeleteConversation(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    const userId = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(DeleteConversationDto, data);
      data = dto;

      const conversation = await this.conversationsService.findById(data.conversationId);

      if (!conversation) {
        client.emit('error', { message: 'Conversation not found' });
        return;
      }

      // Authorization check
      if (conversation.userOne.id !== userId && conversation.userTwo.id !== userId) {
        client.emit('error', { message: 'Unauthorized' });
        return;
      }

      // Get the other user's ID
      const otherUserId = conversation.userOne.id === userId
        ? conversation.userTwo.id
        : conversation.userOne.id;

      this.logger.debug(`deleteConversation: userId=${userId}, otherUserId=${otherUserId}, conversationId=${data.conversationId}`);

      // CRITICAL FIX: Delete the friend relationship first
      // This prevents "Already friends" error when trying to send a new friend request later
      const unfriendResult = await this.friendsService.unfriend(userId, otherUserId);
      this.logger.debug(`deleteConversation: unfriend result=${unfriendResult}`);

      // Then delete the conversation
      await this.conversationsService.delete(data.conversationId);
      this.logger.debug(`deleteConversation: conversation deleted`);

      // Notify the other user
      const otherUserSocketId = this.onlineUsers.get(otherUserId);
      if (otherUserSocketId) {
        this.server.to(otherUserSocketId).emit('unfriended', { userId });
        this.logger.debug(`deleteConversation: notified other user`);
      }

      // Refresh conversations list for current user
      const conversations = await this.conversationsService.findByUser(userId);
      const mapped = conversations.map((c) => ({
        id: c.id,
        userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
        userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
        createdAt: c.createdAt,
      }));
      client.emit('conversationsList', mapped);

      // Refresh conversations list for other user
      if (otherUserSocketId) {
        const otherConversations = await this.conversationsService.findByUser(otherUserId);
        const otherMapped = otherConversations.map((c) => ({
          id: c.id,
          userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
          userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
          createdAt: c.createdAt,
        }));
        this.server.to(otherUserSocketId).emit('conversationsList', otherMapped);
      }

      // Refresh friends lists for both users
      const currentUserFriends = await this.friendsService.getFriends(userId);
      client.emit('friendsList', currentUserFriends.map(f => ({
        id: f.id, email: f.email, username: f.username,
      })));

      if (otherUserSocketId) {
        const otherUserFriends = await this.friendsService.getFriends(otherUserId);
        this.server.to(otherUserSocketId).emit('friendsList', otherUserFriends.map(f => ({
          id: f.id, email: f.email, username: f.username,
        })));
      }

      this.logger.debug(`deleteConversation: all updates sent`);
    } catch (error) {
      this.logger.error('deleteConversation ERROR:', error);
      client.emit('error', { message: error.message });
    }
  }

  // Send a friend request by recipient email
  @SubscribeMessage('sendFriendRequest')
  async handleSendFriendRequest(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
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
    const recipient = await this.usersService.findByEmail(data.recipientEmail);

    if (!sender || !recipient) {
      client.emit('error', { message: 'User not found' });
      return;
    }

    try {
      this.logger.debug(`sendFriendRequest: sender=${sender.email} (id=${sender.id}), recipient=${recipient.email} (id=${recipient.id})`);
      const friendRequest = await this.friendsService.sendRequest(sender, recipient);
      this.logger.debug(`sendFriendRequest: created request id=${friendRequest.id}, status=${friendRequest.status}`);

      const payload = {
        id: friendRequest.id,
        sender: { id: sender.id, email: sender.email, username: sender.username },
        receiver: { id: recipient.id, email: recipient.email, username: recipient.username },
        status: friendRequest.status,
        createdAt: friendRequest.createdAt,
        respondedAt: friendRequest.respondedAt,
      };

      // Check if it was auto-accepted (mutual request scenario)
      if (friendRequest.status === 'accepted') {
        this.logger.debug(`Auto-accept: ${sender.email} <-> ${recipient.email}`);

        // It was auto-accepted! Emit acceptance events to both users
        client.emit('friendRequestAccepted', payload);

        const recipientSocketId = this.onlineUsers.get(recipient.id);
        if (recipientSocketId) {
          this.server.to(recipientSocketId).emit('friendRequestAccepted', payload);
        }

        // Emit updated friends lists to both
        const senderFriends = await this.friendsService.getFriends(sender.id);
        const receiverFriends = await this.friendsService.getFriends(recipient.id);

        client.emit('friendsList', senderFriends.map(f => ({
          id: f.id, email: f.email, username: f.username
        })));

        if (recipientSocketId) {
          this.server.to(recipientSocketId).emit('friendsList', receiverFriends.map(f => ({
            id: f.id, email: f.email, username: f.username
          })));
        }

        // Create conversation between the two users
        const conversation = await this.conversationsService.findOrCreate(sender, recipient);
        this.logger.debug(`Auto-accept: conversation created/found id=${conversation.id}`);

        // Refresh conversations for both users
        const senderConversations = await this.conversationsService.findByUser(sender.id);
        const senderMapped = senderConversations.map((c) => ({
          id: c.id,
          userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
          userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
          createdAt: c.createdAt,
        }));

        client.emit('conversationsList', senderMapped);

        if (recipientSocketId) {
          const receiverConversations = await this.conversationsService.findByUser(recipient.id);
          const receiverMapped = receiverConversations.map((c) => ({
            id: c.id,
            userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
            userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
            createdAt: c.createdAt,
          }));
          this.server.to(recipientSocketId).emit('conversationsList', receiverMapped);
        }

        // Emit openConversation for both users
        client.emit('openConversation', { conversationId: conversation.id });

        if (recipientSocketId) {
          this.server.to(recipientSocketId).emit('openConversation', {
            conversationId: conversation.id
          });
        }

        // Update pending counts for both
        const senderCount = await this.friendsService.getPendingRequestCount(sender.id);
        client.emit('pendingRequestsCount', { count: senderCount });
        if (recipientSocketId) {
          const receiverCount = await this.friendsService.getPendingRequestCount(recipient.id);
          this.server.to(recipientSocketId).emit('pendingRequestsCount', { count: receiverCount });
        }
      } else {
        // Normal pending request flow
        // Notify sender
        this.logger.debug(`sendFriendRequest: emitting friendRequestSent to sender ${sender.email}`);
        client.emit('friendRequestSent', payload);

        // Notify recipient if online
        const recipientSocketId = this.onlineUsers.get(recipient.id);
        this.logger.debug(`sendFriendRequest: recipient ${recipient.email} (id=${recipient.id}) socketId=${recipientSocketId || 'OFFLINE'}`);
        if (recipientSocketId) {
          this.server.to(recipientSocketId).emit('newFriendRequest', payload);
          // Also send updated count
          const count = await this.friendsService.getPendingRequestCount(recipient.id);
          this.server.to(recipientSocketId).emit('pendingRequestsCount', { count });
          this.logger.debug(`sendFriendRequest: emitted newFriendRequest + pendingRequestsCount(${count}) to recipient`);
        }
      }
    } catch (error) {
      this.logger.error(`sendFriendRequest ERROR: ${error.message}`);
      client.emit('error', { message: error.message });
    }
  }

  // Accept a friend request
  @SubscribeMessage('acceptFriendRequest')
  async handleAcceptFriendRequest(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
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

    try {
      this.logger.debug(`acceptFriendRequest: requestId=${data.requestId}, userId=${userId}`);
      const friendRequest = await this.friendsService.acceptRequest(data.requestId, userId);
      this.logger.debug(`acceptFriendRequest: accepted, sender=${friendRequest.sender.id} (${friendRequest.sender.email}), receiver=${friendRequest.receiver.id} (${friendRequest.receiver.email})`);

      const payload = {
        id: friendRequest.id,
        sender: { id: friendRequest.sender.id, email: friendRequest.sender.email, username: friendRequest.sender.username },
        receiver: { id: friendRequest.receiver.id, email: friendRequest.receiver.email, username: friendRequest.receiver.username },
        status: friendRequest.status,
        createdAt: friendRequest.createdAt,
        respondedAt: friendRequest.respondedAt,
      };

      // Notify both users
      client.emit('friendRequestAccepted', payload);

      const senderSocketId = this.onlineUsers.get(friendRequest.sender.id);
      if (senderSocketId) {
        this.server.to(senderSocketId).emit('friendRequestAccepted', payload);
      }

      // Create conversation between the two users so they appear on each other's lists
      const senderUser = await this.usersService.findById(friendRequest.sender.id);
      const receiverUser = await this.usersService.findById(friendRequest.receiver.id);
      let conversation: any = null;
      if (senderUser && receiverUser) {
        conversation = await this.conversationsService.findOrCreate(senderUser, receiverUser);
        this.logger.debug(`acceptFriendRequest: conversation id=${conversation.id}`);
      }

      // Refresh conversations for both
      const senderConversations = await this.conversationsService.findByUser(friendRequest.sender.id);
      const senderMapped = senderConversations.map((c) => ({
        id: c.id,
        userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
        userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
        createdAt: c.createdAt,
      }));

      if (senderSocketId) {
        this.server.to(senderSocketId).emit('conversationsList', senderMapped);
      }

      const receiverConversations = await this.conversationsService.findByUser(userId);
      const receiverMapped = receiverConversations.map((c) => ({
        id: c.id,
        userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
        userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
        createdAt: c.createdAt,
      }));
      client.emit('conversationsList', receiverMapped);

      // Update request list and pending count
      const pendingRequests = await this.friendsService.getPendingRequests(userId);
      const mapped = pendingRequests.map((r) => ({
        id: r.id,
        sender: { id: r.sender.id, email: r.sender.email, username: r.sender.username },
        receiver: { id: r.receiver.id, email: r.receiver.email, username: r.receiver.username },
        status: r.status,
        createdAt: r.createdAt,
        respondedAt: r.respondedAt,
      }));
      client.emit('friendRequestsList', mapped);

      const pendingCount = await this.friendsService.getPendingRequestCount(userId);
      client.emit('pendingRequestsCount', { count: pendingCount });

      // Emit updated friends lists to BOTH users
      const senderFriends = await this.friendsService.getFriends(friendRequest.sender.id);
      this.logger.debug(`acceptFriendRequest: senderFriends count=${senderFriends.length}`);
      const senderFriendsPayload = senderFriends.map((f) => ({
        id: f.id,
        email: f.email,
        username: f.username,
      }));

      const receiverFriends = await this.friendsService.getFriends(userId);
      this.logger.debug(`acceptFriendRequest: receiverFriends count=${receiverFriends.length}`);
      const receiverFriendsPayload = receiverFriends.map((f) => ({
        id: f.id,
        email: f.email,
        username: f.username,
      }));

      // Send to sender (if online)
      if (senderSocketId) {
        this.server.to(senderSocketId).emit('friendsList', senderFriendsPayload);
      }

      // Send to receiver (current user)
      client.emit('friendsList', receiverFriendsPayload);

      // Emit openConversation to navigate both users to the chat
      if (conversation) {
        this.logger.debug(`acceptFriendRequest: emitting openConversation id=${conversation.id}`);
        client.emit('openConversation', { conversationId: conversation.id });

        if (senderSocketId) {
          this.server.to(senderSocketId).emit('openConversation', {
            conversationId: conversation.id
          });
        }
      }
    } catch (error) {
      this.logger.error('acceptFriendRequest ERROR:', error);
      client.emit('error', { message: error.message });
    }
  }

  // Reject a friend request
  @SubscribeMessage('rejectFriendRequest')
  async handleRejectFriendRequest(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(RejectFriendRequestDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    try {
      const friendRequest = await this.friendsService.rejectRequest(data.requestId, userId);

      const payload = {
        id: friendRequest.id,
        sender: { id: friendRequest.sender.id, email: friendRequest.sender.email, username: friendRequest.sender.username },
        receiver: { id: friendRequest.receiver.id, email: friendRequest.receiver.email, username: friendRequest.receiver.username },
        status: friendRequest.status,
        createdAt: friendRequest.createdAt,
        respondedAt: friendRequest.respondedAt,
      };

      // Notify receiver (silently, sender doesn't know)
      client.emit('friendRequestRejected', payload);

      // Update request list
      const pendingRequests = await this.friendsService.getPendingRequests(userId);
      const mapped = pendingRequests.map((r) => ({
        id: r.id,
        sender: { id: r.sender.id, email: r.sender.email, username: r.sender.username },
        receiver: { id: r.receiver.id, email: r.receiver.email, username: r.receiver.username },
        status: r.status,
        createdAt: r.createdAt,
        respondedAt: r.respondedAt,
      }));
      client.emit('friendRequestsList', mapped);

      // Update pending count
      const count = await this.friendsService.getPendingRequestCount(userId);
      client.emit('pendingRequestsCount', { count });
    } catch (error) {
      client.emit('error', { message: error.message });
    }
  }

  // Get pending friend requests for current user
  @SubscribeMessage('getFriendRequests')
  async handleGetFriendRequests(@ConnectedSocket() client: Socket) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const pendingRequests = await this.friendsService.getPendingRequests(userId);
      client.emit('friendRequestsList', FriendRequestMapper.toPayloadArray(pendingRequests));

      const count = await this.friendsService.getPendingRequestCount(userId);
      client.emit('pendingRequestsCount', { count });
    } catch (error) {
      client.emit('error', { message: error.message });
    }
  }

  // Get friends list
  @SubscribeMessage('getFriends')
  async handleGetFriends(@ConnectedSocket() client: Socket) {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const friends = await this.friendsService.getFriends(userId);
      client.emit('friendsList', UserMapper.toPayloadArray(friends));
    } catch (error) {
      client.emit('error', { message: error.message });
    }
  }

  // Unfriend a user and delete conversation
  @SubscribeMessage('unfriend')
  async handleUnfriend(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
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

    try {
      this.logger.debug(`handleUnfriend: currentUserId=${currentUserId}, targetUserId=${data.userId}`);

      // Delete the friend relationship
      await this.friendsService.unfriend(currentUserId, data.userId);

      // Delete the conversation
      const conversation = await this.conversationsService.findByUsers(currentUserId, data.userId);
      if (conversation) {
        await this.conversationsService.delete(conversation.id);
        this.logger.debug(`handleUnfriend: deleted conversation id=${conversation.id}`);
      }

      // Notify both users
      const notifyPayload = { userId: currentUserId };

      client.emit('unfriended', notifyPayload);

      const otherUserSocketId = this.onlineUsers.get(data.userId);
      if (otherUserSocketId) {
        this.server.to(otherUserSocketId).emit('unfriended', { userId: currentUserId });
      }

      // Refresh conversations for both
      const conversations = await this.conversationsService.findByUser(currentUserId);
      const mapped = conversations.map((c) => ({
        id: c.id,
        userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
        userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
        createdAt: c.createdAt,
      }));
      client.emit('conversationsList', mapped);

      if (otherUserSocketId) {
        const otherConversations = await this.conversationsService.findByUser(data.userId);
        const otherMapped = otherConversations.map((c) => ({
          id: c.id,
          userOne: { id: c.userOne.id, email: c.userOne.email, username: c.userOne.username },
          userTwo: { id: c.userTwo.id, email: c.userTwo.email, username: c.userTwo.username },
          createdAt: c.createdAt,
        }));
        this.server.to(otherUserSocketId).emit('conversationsList', otherMapped);
      }

      // Emit updated friends lists to BOTH users
      const currentUserFriends = await this.friendsService.getFriends(currentUserId);
      client.emit('friendsList', currentUserFriends.map(f => ({
        id: f.id, email: f.email, username: f.username,
      })));
      this.logger.debug(`handleUnfriend: emitted friendsList to currentUser, count=${currentUserFriends.length}`);

      if (otherUserSocketId) {
        const otherUserFriends = await this.friendsService.getFriends(data.userId);
        this.server.to(otherUserSocketId).emit('friendsList', otherUserFriends.map(f => ({
          id: f.id, email: f.email, username: f.username,
        })));
        this.logger.debug(`handleUnfriend: emitted friendsList to otherUser, count=${otherUserFriends.length}`);
      }
    } catch (error) {
      this.logger.error('handleUnfriend ERROR:', error);
      client.emit('error', { message: error.message });
    }
  }
}
