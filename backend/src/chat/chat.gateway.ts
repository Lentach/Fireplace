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
        this.logger.debug(
          '[auth-access-reject] reason=missing_access source=socket_connect',
        );
        client.disconnect();
        return;
      }

      const payload = this.jwtService.verify<{ sub: number; iat?: number }>(
        token,
      );
      const user = await this.usersService.findById(payload.sub);

      if (!user) {
        this.logger.debug(
          `[auth-access-reject] reason=user_missing source=socket_connect userId=${payload.sub}`,
        );
        client.disconnect();
        return;
      }

      // Mirror JwtStrategy: a token issued before the last password change is invalid.
      if (user.passwordChangedAt) {
        const changedAtSeconds = Math.floor(
          user.passwordChangedAt.getTime() / 1000,
        );
        if (
          typeof payload.iat === 'number' &&
          payload.iat <= changedAtSeconds
        ) {
          this.logger.debug(
            `[auth-access-reject] reason=password_changed source=socket_connect userId=${user.id}`,
          );
          client.disconnect();
          return;
        }
      }

      client.data.user = {
        id: user.id,
        username: user.username,
        tag: user.tag,
      };
      client.join(ChatKeyExchangeService.userRoom(user.id));
      this.onlineUsers.set(user.id, client.id);
      this.chatKeyExchangeService.deliverPendingSessionRebuilds(client);

      this.logger.debug(
        `User connected: ${user.username} (socket: ${client.id})`,
      );
      // Auth is complete — client may safely emit authenticated WS events.
      // `serverTime` is the client's only trustworthy clock reference. It
      // gates destroying expired message plaintext, which is irreversible:
      // the client holds ciphertext it can no longer decrypt, so a device with
      // a fast wall clock would otherwise wipe messages still live here. An
      // older client ignores the field; a newer client against an older server
      // sees none and simply never destroys on expiry.
      client.emit('socketReady', { serverTime: new Date().toISOString() });
    } catch (error) {
      const errorName =
        error instanceof Error ? error.name : 'UnknownSocketAuthError';
      const reason =
        errorName === 'TokenExpiredError'
          ? 'access_expired'
          : errorName === 'JsonWebTokenError'
            ? 'invalid_signature'
            : 'access_invalid';
      const line = `[auth-access-reject] reason=${reason} source=socket_connect errorType=${errorName}`;
      if (reason === 'invalid_signature') {
        this.logger.warn(line);
      } else {
        this.logger.debug(line);
      }
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    const user = client.data.user;
    if (!user) return;
    // Only unregister if THIS socket is still the user's current one. On iOS
    // suspend/resume the device reconnects with a NEW socket while the abandoned
    // OLD socket lingers until its ping times out (~20s); that stale disconnect
    // must NOT evict the live socket — otherwise onlineUsers.get(userId) goes
    // undefined and peers' newMessage emits silently fall back to push (the
    // "notification arrives but the message never appears live" bug).
    if (this.onlineUsers.get(user.id) === client.id) {
      this.onlineUsers.delete(user.id);
    }
    this.logger.debug(
      `User disconnected: ${user.username} (socket: ${client.id})`,
    );
  }

  // ========== MESSAGE HANDLERS ==========

  /** Per-user cap for outgoing messages; global ThrottlerModule default is 100/15min — too low for active chat. */
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 300, ttl: 900000 } })
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

  /**
   * Local-plaintext reconciliation. Cheap (PK lookup + two predicates), and the
   * client throttles itself to a few passes a day, so the limit sits well under
   * `getMessages`.
   */
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('getServedMessageIds')
  async handleGetServedMessageIds(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: unknown,
  ) {
    return this.chatMessageService.handleGetServedMessageIds(client, data);
  }

  /**
   * Server-clock refresh for the client's in-session expiry sweep. The
   * `socketReady` observation ages out of client trust after ~30 minutes
   * (never extrapolated further); without a refresh, a connection that stays
   * up longer than that could never destroy expired plaintext until its next
   * reconnect. Stateless, no DB. The client asks roughly once per half hour,
   * so the limit sits far above real traffic.
   */
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('getServerTime')
  handleGetServerTime(@ConnectedSocket() client: Socket) {
    client.emit('serverTime', { serverTime: new Date().toISOString() });
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('editMessage')
  handleEditMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatMessageService.handleEditMessage(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  // ========== TYPING INDICATOR ==========

  @SubscribeMessage('typing')
  async handleTyping(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ): Promise<void> {
    return this.chatPresenceService.handleTyping(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 120, ttl: 900000 } })
  @SubscribeMessage('addReaction')
  async handleAddReaction(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatReactionService.handleAddReaction(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 120, ttl: 900000 } })
  @SubscribeMessage('removeReaction')
  async handleRemoveReaction(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatReactionService.handleRemoveReaction(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @SubscribeMessage('recordingVoice')
  async handleRecordingVoice(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ): Promise<void> {
    return this.chatPresenceService.handleRecordingVoice(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  /** Lets client suppress push when already viewing this conversation (foreground + active chat). */
  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 120, ttl: 900000 } })
  @SubscribeMessage('pushClientState')
  handlePushClientState(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ): void {
    return this.chatPresenceService.handlePushClientState(client, data);
  }

  // ========== KEY EXCHANGE HANDLERS (E2E Encryption) ==========

  @SubscribeMessage('uploadKeyBundle')
  async handleUploadKeyBundle(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatKeyExchangeService.handleUploadKeyBundle(client, data);
  }

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 900000 } })
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('setConversationMute')
  async handleSetConversationMute(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: unknown,
  ) {
    return this.chatConversationService.handleSetConversationMute(client, data);
  }

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('pinMessage')
  async handlePinMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatConversationService.handlePinMessage(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
  }

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 900000 } })
  @SubscribeMessage('unpinMessage')
  async handleUnpinMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatConversationService.handleUnpinMessage(
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
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
      this.server,
      this.onlineUsers,
    );
  }

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
  @SubscribeMessage('ensureInvitationChat')
  async handleEnsureInvitationChat(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: unknown,
  ) {
    return this.chatFriendRequestService.handleEnsureInvitationChat(
      client,
      data,
      this.server,
      this.onlineUsers,
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
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

  @UseGuards(WsThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
  @SubscribeMessage('blockUser')
  async handleBlockUser(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    return this.chatBlockService.handleBlockUser(
      client,
      data,
      this.server,
      this.onlineUsers,
    );
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
