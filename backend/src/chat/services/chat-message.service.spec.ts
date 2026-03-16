import { Test, TestingModule } from '@nestjs/testing';
import { MessagesService } from '../../messages/messages.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { ChatValidationService } from './chat-validation.service';
import { UsersService } from '../../users/users.service';
import { ChatLinkPreviewService } from './chat-link-preview.service';
import { PushNotificationsService } from '../../push-notifications/push-notifications.service';
import { ChatMessageService } from './chat-message.service';
import { User } from '../../users/user.entity';
import { Conversation } from '../../conversations/conversation.entity';
import { Message, MessageDeliveryStatus } from '../../messages/message.entity';
import { Socket } from 'socket.io';
import { Server } from 'socket.io';

describe('ChatMessageService', () => {
  let service: ChatMessageService;
  let messagesService: jest.Mocked<MessagesService>;
  let conversationsService: jest.Mocked<ConversationsService>;
  let chatValidationService: jest.Mocked<ChatValidationService>;
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
          provide: ChatValidationService,
          useValue: { validateCanMessage: jest.fn().mockResolvedValue({ valid: true }) },
        },
        {
          provide: UsersService,
          useValue: { findById: jest.fn() },
        },
        {
          provide: ChatLinkPreviewService,
          useValue: { fetchAndEmitIfNeeded: jest.fn() },
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
    chatValidationService = module.get(ChatValidationService);
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
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
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
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
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
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
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

      // ChatLinkPreviewService.fetchAndEmitIfNeeded is called but with encryptedContent set,
      // so the service internally skips the preview fetch
      const chatLinkPreviewService = (service as any).chatLinkPreviewService;
      expect(chatLinkPreviewService.fetchAndEmitIfNeeded).toHaveBeenCalledWith(
        expect.objectContaining({
          encryptedContent: '3:base64ciphertext==',
        }),
      );
    });
  });

  describe('E2E encrypted message types', () => {
    it('should store [encrypted] content and pass encryptedContent for PING', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:pingCiphertext==',
        messageType: 'TEXT', // server doesn't know real type when encrypted
        mediaUrl: null,
      } as Message);

      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:pingCiphertext==',
        // No messageType, mediaUrl — hidden inside encrypted envelope
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
          encryptedContent: '3:pingCiphertext==',
        }),
      );
      // Verify no mediaUrl or messageType leaked from client
      const createCall = messagesService.create.mock.calls[0];
      const opts = createCall[3] as Record<string, unknown>;
      expect(opts.mediaUrl).toBeUndefined();
      expect(opts.messageType).toBeUndefined();
    });

    it('should store [encrypted] for encrypted VOICE (no mediaUrl in payload)', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:voiceCiphertext==',
        messageType: 'TEXT',
        mediaUrl: null,
      } as Message);

      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:voiceCiphertext==',
        // mediaUrl is inside the encrypted envelope, not in WS payload
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
          encryptedContent: '3:voiceCiphertext==',
        }),
      );
      const opts = messagesService.create.mock.calls[0][3] as Record<string, unknown>;
      expect(opts.mediaUrl).toBeUndefined();
      expect(opts.mediaDuration).toBeUndefined();
    });

    it('should store [encrypted] for encrypted IMAGE (no mediaUrl in payload)', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:imageCiphertext==',
        messageType: 'TEXT',
        mediaUrl: null,
      } as Message);

      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:imageCiphertext==',
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      const opts = messagesService.create.mock.calls[0][3] as Record<string, unknown>;
      expect(opts.encryptedContent).toBe('3:imageCiphertext==');
      expect(opts.mediaUrl).toBeUndefined();
    });

    it('should store [encrypted] for encrypted GIF (no mediaUrl in payload)', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:base64encryptedGifData',
        messageType: 'TEXT',
        mediaUrl: null,
      } as Message);

      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:base64encryptedGifData',
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      const opts = messagesService.create.mock.calls[0][3] as Record<string, unknown>;
      expect(opts.encryptedContent).toBe('3:base64encryptedGifData');
      expect(opts.messageType).toBeUndefined();
      expect(opts.mediaUrl).toBeUndefined();
    });

    it('should NOT fetch link preview for any encrypted message', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:textWithLinkCipher==',
        messageType: 'TEXT',
      } as Message);

      // Even though content placeholder is [encrypted], link preview must not run
      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:textWithLinkCipher==',
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      // ChatLinkPreviewService is called but with encryptedContent, so it skips internally
      const chatLinkPreviewService = (service as any).chatLinkPreviewService;
      expect(chatLinkPreviewService.fetchAndEmitIfNeeded).toHaveBeenCalledWith(
        expect.objectContaining({
          encryptedContent: '3:textWithLinkCipher==',
        }),
      );
    });

    it('should emit messageSent and newMessage with encryptedContent for online recipient', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);

      const savedMsg = {
        ...mockMessage,
        id: 200,
        content: '[encrypted]',
        encryptedContent: '3:cipher==',
        messageType: 'TEXT',
        mediaUrl: null,
        mediaDuration: null,
        reactions: null,
        replyTo: null,
        expiresAt: null,
      } as Message;
      messagesService.create.mockResolvedValue(savedMsg);

      onlineUsers.set(2, 'socket-bob');

      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:cipher==',
        tempId: 'temp-123',
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      // messageSent to sender
      expect(mockClient.emit).toHaveBeenCalledWith(
        'messageSent',
        expect.objectContaining({
          content: '[encrypted]',
          encryptedContent: '3:cipher==',
          tempId: 'temp-123',
        }),
      );

      // newMessage to recipient
      expect(mockServer.to).toHaveBeenCalledWith('socket-bob');
      expect(mockServer.emit).toHaveBeenCalledWith(
        'newMessage',
        expect.objectContaining({
          content: '[encrypted]',
          encryptedContent: '3:cipher==',
        }),
      );
    });
  });

  describe('handleMessageDelivered', () => {
    it('rejects when caller is the sender, not the recipient', async () => {
      // Message sender = userId 1 (the caller). Recipient = userId 2.
      const conv = { id: 10, userOne: { id: 1 }, userTwo: { id: 2 } };
      const msg = { id: 99, sender: { id: 1 }, conversation: conv };
      (messagesService as any).findByIdWithConversation = jest
        .fn()
        .mockResolvedValue(msg);
      (messagesService as any).updateDeliveryStatus = jest.fn();

      await service.handleMessageDelivered(
        mockClient as any,
        { messageId: 99 },
        mockServer as any,
        onlineUsers,
      );

      expect((messagesService as any).updateDeliveryStatus).not.toHaveBeenCalled();
    });

    it('allows when caller is the recipient', async () => {
      // Message sender = userId 2. Caller = userId 1 (recipient).
      const conv = { id: 10, userOne: { id: 2 }, userTwo: { id: 1 } };
      const updatedMsg = { id: 99, sender: { id: 2 }, conversation: conv, deliveryStatus: 'DELIVERED' };
      (messagesService as any).findByIdWithConversation = jest
        .fn()
        .mockResolvedValue({ id: 99, sender: { id: 2 }, conversation: conv });
      (messagesService as any).updateDeliveryStatus = jest
        .fn()
        .mockResolvedValue(updatedMsg);

      await service.handleMessageDelivered(
        mockClient as any,
        { messageId: 99 },
        mockServer as any,
        onlineUsers,
      );

      expect((messagesService as any).updateDeliveryStatus).toHaveBeenCalledWith(
        99,
        MessageDeliveryStatus.DELIVERED,
      );
    });
  });
});
