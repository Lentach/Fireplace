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
import { UsersService } from '../users/users.service';
import { ConversationsService } from '../conversations/conversations.service';
import { MessagesService } from '../messages/messages.service';

// cors: '*' — simplified for MVP, set a specific domain in production
@WebSocketGateway({ cors: { origin: '*' } })
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  // Map: userId -> socketId, to track who is online
  private onlineUsers = new Map<number, string>();

  constructor(
    private jwtService: JwtService,
    private usersService: UsersService,
    private conversationsService: ConversationsService,
    private messagesService: MessagesService,
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
      client.data.user = { id: user.id, email: user.email };
      this.onlineUsers.set(user.id, client.id);

      console.log(`User connected: ${user.email} (socket: ${client.id})`);
    } catch {
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    if (client.data.user) {
      this.onlineUsers.delete(client.data.user.id);
      console.log(`User disconnected: ${client.data.user.email}`);
    }
  }

  // Client sends: { recipientId: number, content: string }
  // Server:
  //   1. Finds or creates a conversation
  //   2. Saves the message to the database
  //   3. Sends the message to the recipient (if online)
  //   4. Confirms to the sender
  @SubscribeMessage('sendMessage')
  async handleMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { recipientId: number; content: string },
  ) {
    const senderId: number = client.data.user?.id;
    if (!senderId) return;

    const sender = await this.usersService.findById(senderId);
    const recipient = await this.usersService.findById(data.recipientId);

    if (!sender || !recipient) {
      client.emit('error', { message: 'User not found' });
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
    @MessageBody() data: { recipientEmail: string },
  ) {
    console.log('startConversation received, data:', JSON.stringify(data));
    const senderId: number = client.data.user?.id;
    if (!senderId) {
      console.log('startConversation: no senderId');
      return;
    }

    const sender = await this.usersService.findById(senderId);
    const recipient = await this.usersService.findByEmail(data.recipientEmail);
    console.log('startConversation: sender=', sender?.email, 'recipient=', recipient?.email, 'recipientEmail=', data.recipientEmail);

    if (!sender || !recipient) {
      console.log('startConversation: user not found, emitting error');
      client.emit('error', { message: 'User not found' });
      return;
    }

    if (sender.id === recipient.id) {
      client.emit('error', { message: 'Cannot chat with yourself' });
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
      userOne: { id: c.userOne.id, email: c.userOne.email },
      userTwo: { id: c.userTwo.id, email: c.userTwo.email },
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
    @MessageBody() data: { conversationId: number },
  ) {
    const messages = await this.messagesService.findByConversation(
      data.conversationId,
    );

    const mapped = messages.map((m) => ({
      id: m.id,
      content: m.content,
      senderId: m.sender.id,
      senderEmail: m.sender.email,
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

    const mapped = conversations.map((c) => ({
      id: c.id,
      userOne: { id: c.userOne.id, email: c.userOne.email },
      userTwo: { id: c.userTwo.id, email: c.userTwo.email },
      createdAt: c.createdAt,
    }));

    client.emit('conversationsList', mapped);
  }
}
