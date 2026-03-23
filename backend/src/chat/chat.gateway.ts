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
import { Logger, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { WsThrottlerGuard } from './guards/ws-throttler.guard';
import { UsersService } from '../users/users.service';
import { ChatMessageService } from './services/chat-message.service';
import { ChatFriendRequestService } from './services/chat-friend-request.service';
import { ChatConversationService } from './services/chat-conversation.service';
import { ChatKeyExchangeService } from './services/chat-key-exchange.service';
import { ChatPresenceService } from './services/chat-presence.service';
import { ChatBlockService } from './services/chat-block.service';
import { ChatSearchService } from './services/chat-search.service';
import { ChatReactionService } from './services/chat-reaction.service';

// CORS: In production only ALLOWED_ORIGINS. In dev also allow localhost + LAN (phone).
function buildCorsOrigin() {
  const allowed = (process.env.ALLOWED_ORIGINS || 'http://localhost:3000')
    .split(',')
    .map((o) => o.trim());
  const isProd = process.env.NODE_ENV === 'production';
  return (origin: string, cb: (err: Error | null, allow?: boolean) => void) => {
    if (!origin) {
      cb(null, true);
      return;
    }
    if (allowed.includes(origin)) {
      cb(null, true);
      return;
    }
    if (
      !isProd &&
      (origin.startsWith('http://localhost:') ||
        origin.startsWith('http://127.0.0.1:') ||
        origin.startsWith('http://192.168.') ||
        origin.startsWith('http://10.'))
    ) {
      cb(null, true);
      return;
    }
    cb(new Error('Not allowed by CORS'), false);
  };
}
@WebSocketGateway({
  cors: { origin: buildCorsOrigin() },
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
    private chatMessageService: ChatMessageService,
    private chatFriendRequestService: ChatFriendRequestService,
    private chatConversationService: ChatConversationService,
    private chatKeyExchangeService: ChatKeyExchangeService,
    private chatPresenceService: ChatPresenceService,
    private chatBlockService: ChatBlockService,
    private chatSearchService: ChatSearchService,
    private chatReactionService: ChatReactionService,
  ) {}

  // On WebSocket connection — verify the JWT token.
  async handleConnection(client: Socket) {
    try {
      const token = client.handshake.auth?.token as string;

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

      client.data.user = {
        id: user.id,
        username: user.username,
        tag: user.tag,
      };
      this.onlineUsers.set(user.id, client.id);

      this.logger.debug(`User connected: ${user.username} (socket: ${client.id})`);
    } catch (error) {
      this.logger.error(`handleConnection failed: ${error.message}`);
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    if (client.data.user) {
      this.onlineUsers.delete(client.data.user.id);
      this.logger.debug(`User disconnected: ${client.data.user.username}`);
    }
  }

  // ========== MESSAGE HANDLERS ==========

  /** Per-user cap for outgoing messages; global ThrottlerModule default is 100/15min — too low for active chat. */
  @Throttle({ default: { limit: 300, ttl: 900000 } })
  @UseGuards(WsThrottlerGuard)
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 300, ttl: 900000 } })
  @SubscribeMessage('getMessages')
  async handleGetMessages(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleGetMessages(client, data);
  }

  @SubscribeMessage('messageDelivered')
  async handleMessageDelivered(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleMessageDelivered(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('markConversationRead')
  async handleMarkConversationRead(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleMarkConversationRead(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('clearChatHistory')
  handleClearChatHistory(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleClearChatHistory(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('deleteMessage')
  handleDeleteMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleDeleteMessage(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  // ========== TYPING INDICATOR ==========

  @SubscribeMessage('typing')
  handleTyping(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ): void {
    return this.chatPresenceService.handleTyping(client, data, this.server, this.onlineUsers);
  }

  @SubscribeMessage('addReaction')
  async handleAddReaction(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatReactionService.handleAddReaction(client, data, this.server, this.onlineUsers);
  }

  @SubscribeMessage('removeReaction')
  async handleRemoveReaction(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatReactionService.handleRemoveReaction(client, data, this.server, this.onlineUsers);
  }

  @SubscribeMessage('recordingVoice')
  handleRecordingVoice(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ): void {
    return this.chatPresenceService.handleRecordingVoice(client, data, this.server, this.onlineUsers);
  }

  // ========== KEY EXCHANGE HANDLERS (E2E Encryption) ==========

  @SubscribeMessage('uploadKeyBundle')
  async handleUploadKeyBundle(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatKeyExchangeService.handleUploadKeyBundle(client, data);
  }

  @SubscribeMessage('uploadOneTimePreKeys')
  async handleUploadOneTimePreKeys(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatKeyExchangeService.handleUploadOneTimePreKeys(client, data);
  }

  @UseGuards(WsThrottlerGuard)
  @SubscribeMessage('fetchPreKeyBundle')
  async handleFetchPreKeyBundle(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatKeyExchangeService.handleFetchPreKeyBundle(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('requestSessionRebuild')
  async handleRequestSessionRebuild(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatKeyExchangeService.handleRequestSessionRebuild(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 300, ttl: 900000 } })
  @SubscribeMessage('getConversations')
  async handleGetConversations(@ConnectedSocket() client: Socket) {
    return this.chatConversationService.handleGetConversations(client);
  }

  @SubscribeMessage('deleteConversationOnly')
  async handleDeleteConversationOnly(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    await this.chatConversationService.handleDeleteConversationOnly(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('setDisappearingTimer')
  async handleSetDisappearingTimer(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatConversationService.handleSetDisappearingTimer(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  // ========== FRIEND REQUEST HANDLERS ==========

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 60000 } })
  @SubscribeMessage('searchUsers')
  async handleSearchUsers(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatSearchService.handleSearchUsers(client, data);
  }

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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 300, ttl: 900000 } })
  @SubscribeMessage('getFriendRequests')
  async handleGetFriendRequests(@ConnectedSocket() client: Socket) {
    return this.chatFriendRequestService.handleGetFriendRequests(client);
  }

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 300, ttl: 900000 } })
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

  @SubscribeMessage('blockUser')
  async handleBlockUser(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatBlockService.handleBlockUser(client, data, this.server, this.onlineUsers);
  }

  @SubscribeMessage('unblockUser')
  async handleUnblockUser(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatBlockService.handleUnblockUser(client, data);
  }

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 300, ttl: 900000 } })
  @SubscribeMessage('getBlockedList')
  async handleGetBlockedList(@ConnectedSocket() client: Socket) {
    return this.chatBlockService.handleGetBlockedList(client);
  }
}
