import { Test, TestingModule } from '@nestjs/testing';
import { MessagesService } from '../../messages/messages.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { FriendsService } from '../../friends/friends.service';
import { UsersService } from '../../users/users.service';
import { BlockedService } from '../../blocked/blocked.service';
import { LinkPreviewService } from './link-preview.service';
import { PushNotificationsService } from '../../push-notifications/push-notifications.service';
import { ChatMessageService } from './chat-message.service';
import { User } from '../../users/user.entity';
import { Conversation } from '../../conversations/conversation.entity';
import { Message } from '../../messages/message.entity';
import { Socket } from 'socket.io';
import { Server } from 'socket.io';

describe('ChatMessageService', () => {
  let service: ChatMessageService;
  let messagesService: jest.Mocked<MessagesService>;
  let conversationsService: jest.Mocked<ConversationsService>;
  let friendsService: jest.Mocked<FriendsService>;
  let usersService: jest.Mocked<UsersService>;

  const mockSender: Partial<User> = { id: 1, username: 'alice' };
  const mockRecipient: Partial<User> = { id: 2, username: 'bob' };
  const mockConversation: Partial<Conversation> = { id: 10 };
  const mockMessage = {
    id: 100,
    content: '',
    sender: mockSender,
    conversation: mockConversation,
    createdAt: new Date(),
    deliveryStatus: 'SENT',
    messageType: 'VOICE',
    mediaUrl: 'https://res.cloudinary.com/demo/video/upload/v1/x.m4a',
    mediaDuration: 5,
    expiresAt: null,
  } as Message;

  let mockClient: Partial<Socket>;
  let mockServer: Partial<Server>;
  let onlineUsers: Map<number, string>;

  beforeEach(async () => {
    mockClient = {
      data: { user: { id: 1 } },
      emit: jest.fn(),
    };
    mockServer = { to: jest.fn().mockReturnThis(), emit: jest.fn() };
    onlineUsers = new Map();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatMessageService,
        {
          provide: MessagesService,
          useValue: {
            create: jest.fn(),
            findByConversation: jest.fn(),
          },
        },
        {
          provide: ConversationsService,
          useValue: {
            findOrCreate: jest.fn(),
            findById: jest.fn(),
          },
        },
        {
          provide: FriendsService,
          useValue: { areFriends: jest.fn() },
        },
        {
          provide: UsersService,
          useValue: { findById: jest.fn() },
        },
        {
          provide: BlockedService,
          useValue: { isBlockedByEither: jest.fn().mockResolvedValue(false) },
        },
        {
          provide: LinkPreviewService,
          useValue: { fetchPreview: jest.fn().mockResolvedValue(null) },
        },
        {
          provide: PushNotificationsService,
          useValue: { notify: jest.fn().mockResolvedValue(undefined) },
        },
      ],
    }).compile();

    service = module.get<ChatMessageService>(ChatMessageService);
    messagesService = module.get(MessagesService);
    conversationsService = module.get(ConversationsService);
    friendsService = module.get(FriendsService);
    usersService = module.get(UsersService);
    jest.clearAllMocks();
  });

  describe('handleSendMessage', () => {
    it('should reject non-Cloudinary mediaUrl and emit error (no message created)', async () => {
      const data = {
        recipientId: 2,
        content: '',
        messageType: 'VOICE',
        mediaUrl: 'https://evil.com/malicious.mp3',
        mediaDuration: 5,
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        expect.objectContaining({
          message: expect.stringMatching(/Validation failed|Cloudinary/i),
        }),
      );
      expect(messagesService.create).not.toHaveBeenCalled();
    });

    it('should accept valid Cloudinary mediaUrl and create message', async () => {
      friendsService.areFriends.mockResolvedValue(true);
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue(mockMessage as Message);

      const data = {
        recipientId: 2,
        content: '',
        messageType: 'VOICE',
        mediaUrl: 'https://res.cloudinary.com/demo/video/upload/v1/voice-messages/abc.m4a',
        mediaDuration: 5,
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      expect(messagesService.create).toHaveBeenCalledWith(
        '',
        mockSender,
        mockConversation,
        expect.objectContaining({
          messageType: 'VOICE',
          mediaUrl: data.mediaUrl,
          mediaDuration: 5,
        }),
      );
      expect(mockClient.emit).toHaveBeenCalledWith('messageSent', expect.any(Object));
    });
    it('should pass encryptedContent to create and store [encrypted] as content', async () => {
      friendsService.areFriends.mockResolvedValue(true);
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:base64ciphertext==',
        messageType: 'TEXT',
      } as Message);

      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:base64ciphertext==',
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      expect(messagesService.create).toHaveBeenCalledWith(
        '[encrypted]',
        mockSender,
        mockConversation,
        expect.objectContaining({
          encryptedContent: '3:base64ciphertext==',
        }),
      );
      expect(mockClient.emit).toHaveBeenCalledWith('messageSent', expect.any(Object));
    });

    it('should skip link preview when encryptedContent is present', async () => {
      const linkPreviewService = { fetchPreview: jest.fn() };
      friendsService.areFriends.mockResolvedValue(true);
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:base64ciphertext==',
        messageType: 'TEXT',
      } as Message);

      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:base64ciphertext==',
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      // Link preview should not be fetched for encrypted messages
      expect(linkPreviewService.fetchPreview).not.toHaveBeenCalled();
    });
  });
});
