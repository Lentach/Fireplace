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
import { ChatMessageService } from './services/chat-message.service';
import { ChatFriendRequestService } from './services/chat-friend-request.service';
import { ChatConversationService } from './services/chat-conversation.service';

// cors: configured from environment or default to localhost for development
@WebSocketGateway({
  cors: {
    origin: (process.env.ALLOWED_ORIGINS || 'http://localhost:3000')
      .split(',')
      .map((o) => o.trim()),
  },
})
export class ChatGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  private readonly logger = new Logger(ChatGateway.name);

  @WebSocketServer()
  server: Server;

  // Map: userId -> socketId, to track who is online
  private onlineUsers = new Map<number, string>();

  constructor(
    private jwtService: JwtService,
    private usersService: UsersService,
    private chatMessageService: ChatMessageService,
    private chatFriendRequestService: ChatFriendRequestService,
    private chatConversationService: ChatConversationService,
  ) {}

  // On WebSocket connection — verify the JWT token.
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
      client.data.user = {
        id: user.id,
        email: user.email,
        username: user.username,
      };
      this.onlineUsers.set(user.id, client.id);

      this.logger.debug(
        `User connected: ${user.email} (socket: ${client.id})`,
      );
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

  // ========== MESSAGE HANDLERS ==========

  @SubscribeMessage('sendMessage')
  async handleSendMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleSendMessage(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('getMessages')
  async handleGetMessages(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleGetMessages(client, data);
  }

  // ========== CONVERSATION HANDLERS ==========

  @SubscribeMessage('startConversation')
  async handleStartConversation(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatConversationService.handleStartConversation(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('getConversations')
  async handleGetConversations(@ConnectedSocket() client: Socket) {
    return this.chatConversationService.handleGetConversations(client);
  }

  @SubscribeMessage('deleteConversation')
  async handleDeleteConversation(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatConversationService.handleDeleteConversation(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  // ========== FRIEND REQUEST HANDLERS ==========

  @SubscribeMessage('sendFriendRequest')
  async handleSendFriendRequest(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatFriendRequestService.handleSendFriendRequest(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('acceptFriendRequest')
  async handleAcceptFriendRequest(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatFriendRequestService.handleAcceptFriendRequest(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('rejectFriendRequest')
  async handleRejectFriendRequest(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatFriendRequestService.handleRejectFriendRequest(
      client,
      data,
    );
  }

  @SubscribeMessage('getFriendRequests')
  async handleGetFriendRequests(@ConnectedSocket() client: Socket) {
    return this.chatFriendRequestService.handleGetFriendRequests(client);
  }

  @SubscribeMessage('getFriends')
  async handleGetFriends(@ConnectedSocket() client: Socket) {
    return this.chatFriendRequestService.handleGetFriends(client);
  }

  @SubscribeMessage('unfriend')
  async handleUnfriend(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatFriendRequestService.handleUnfriend(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('updateActiveStatus')
  async handleUpdateActiveStatus(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatFriendRequestService.handleUpdateActiveStatus(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }
}
