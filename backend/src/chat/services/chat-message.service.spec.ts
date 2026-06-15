import { Test, TestingModule } from '@nestjs/testing';
import { MessagesService } from '../../messages/messages.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { ChatValidationService } from './chat-validation.service';
import { UsersService } from '../../users/users.service';
import { ChatLinkPreviewService } from './chat-link-preview.service';
import { PushNotificationCoalescingService } from '../../push-notifications/push-notification-coalescing.service';
import { MediaCleanupService } from '../../media/media-cleanup.service';
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
  const mockConversation: Partial<Conversation> = {
    id: 10,
    disappearingTimer: 86400,
  };
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
            findMediaUrlsByConversation: jest.fn().mockResolvedValue([]),
            markConversationAsReadFromSender: jest.fn(),
          },
        },
        {
          provide: ConversationsService,
          useValue: {
            findOrCreate: jest.fn(),
            findById: jest.fn(),
            clearPinnedMessage: jest.fn().mockResolvedValue(undefined),
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
          provide: PushNotificationCoalescingService,
          useValue: {
            scheduleMessagePush: jest.fn().mockResolvedValue(undefined),
          },
        },
        {
          provide: MediaCleanupService,
          useValue: {
            deleteMediaFile: jest.fn().mockResolvedValue(undefined),
          },
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
          message: expect.stringMatching(
            /Validation failed|self-hosted media URL|Cloudinary/i,
          ),
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

    it('should persist mediaUrl and messageType for encrypted VOICE', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:voiceCiphertext==',
        messageType: 'VOICE',
        mediaUrl: 'http://localhost:3000/media/msgs/voice.bin',
      } as Message);

      const mediaUrl = 'http://localhost:3000/media/msgs/voice.bin';
      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:voiceCiphertext==',
        messageType: 'VOICE',
        mediaUrl,
        mediaDuration: 12,
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
          messageType: 'VOICE',
          mediaUrl,
          mediaDuration: 12,
        }),
      );
    });

    it('should persist mediaUrl and messageType for encrypted IMAGE', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:imageCiphertext==',
        messageType: 'IMAGE',
        mediaUrl: 'http://localhost:3000/media/msgs/image.bin',
      } as Message);

      const mediaUrl = 'http://localhost:3000/media/msgs/image.bin';
      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:imageCiphertext==',
        messageType: 'IMAGE',
        mediaUrl,
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      const opts = messagesService.create.mock.calls[0][3] as Record<string, unknown>;
      expect(opts.encryptedContent).toBe('3:imageCiphertext==');
      expect(opts.messageType).toBe('IMAGE');
      expect(opts.mediaUrl).toBe(mediaUrl);
    });

    it('should persist mediaUrl and messageType for encrypted GIF', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:base64encryptedGifData',
        messageType: 'GIF',
        mediaUrl: 'http://localhost:3000/media/msgs/gif.bin',
      } as Message);

      const mediaUrl = 'http://localhost:3000/media/msgs/gif.bin';
      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:base64encryptedGifData',
        messageType: 'GIF',
        mediaUrl,
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      const opts = messagesService.create.mock.calls[0][3] as Record<string, unknown>;
      expect(opts.encryptedContent).toBe('3:base64encryptedGifData');
      expect(opts.messageType).toBe('GIF');
      expect(opts.mediaUrl).toBe(mediaUrl);
    });

    it('should persist mediaUrl and messageType for encrypted FILE', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: '[encrypted]',
        encryptedContent: '3:base64encryptedFileData',
        messageType: 'FILE',
        mediaUrl: 'http://localhost:3000/media/msgs/file.bin',
      } as Message);

      const mediaUrl = 'http://localhost:3000/media/msgs/file.bin';
      const data = {
        recipientId: 2,
        content: '[encrypted]',
        encryptedContent: '3:base64encryptedFileData',
        messageType: 'FILE',
        mediaUrl,
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
        onlineUsers,
      );

      const opts = messagesService.create.mock.calls[0][3] as Record<string, unknown>;
      expect(opts.encryptedContent).toBe('3:base64encryptedFileData');
      expect(opts.messageType).toBe('FILE');
      expect(opts.mediaUrl).toBe(mediaUrl);
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

  describe('read-based disappearing messages', () => {
    it('stores disappearAfterSeconds with null expiresAt on send', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(mockConversation as Conversation);
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        disappearAfterSeconds: 300,
        expiresAt: null,
      } as Message);

      await service.handleSendMessage(
        mockClient as Socket,
        { recipientId: 2, content: 'hi', expiresIn: 300 },
        mockServer as Server,
        onlineUsers,
      );

      expect(messagesService.create).toHaveBeenCalledWith(
        'hi',
        mockSender,
        mockConversation,
        expect.objectContaining({
          disappearAfterSeconds: 300,
          expiresAt: null,
        }),
      );
    });

    it('handleMarkConversationRead emits expiresAt to sender and reader', async () => {
      const conv = {
        id: 10,
        userOne: { id: 1 },
        userTwo: { id: 2 },
      };
      const expiresAt = new Date('2026-05-17T13:00:00Z');
      const updatedMsg = {
        id: 50,
        sender: { id: 2 },
        deliveryStatus: MessageDeliveryStatus.READ,
        expiresAt,
        disappearAfterSeconds: 3600,
      } as Message;

      conversationsService.findById.mockResolvedValue(conv as Conversation);
      messagesService.markConversationAsReadFromSender.mockResolvedValue([
        updatedMsg,
      ]);
      onlineUsers.set(1, 'sock-reader');
      onlineUsers.set(2, 'sock-sender');
      const toMock = jest.fn().mockReturnValue({ emit: jest.fn() });
      mockServer.to = toMock;

      mockClient.data = { user: { id: 1 } };

      await service.handleMarkConversationRead(
        mockClient as Socket,
        { conversationId: 10 },
        mockServer as Server,
        onlineUsers,
      );

      expect(messagesService.markConversationAsReadFromSender).toHaveBeenCalledWith(
        10,
        2,
      );
      expect(toMock).toHaveBeenCalledWith('sock-sender');
      expect(toMock).toHaveBeenCalledWith('sock-reader');
      const emitCalls = toMock.mock.results.map((r) => r.value.emit.mock.calls);
      expect(emitCalls.some((calls) =>
        calls.some(
          (c) =>
            c[0] === 'messageDelivered' &&
            c[1].expiresAt === expiresAt.toISOString(),
        ),
      )).toBe(true);
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

  describe('handleDeleteMessage', () => {
    it('clears pin and emits messageUnpinned when deleting pinned message for everyone', async () => {
      const conv = {
        id: 10,
        userOne: { id: 1 },
        userTwo: { id: 2 },
        pinnedMessageId: 55,
      };
      const msg = {
        id: 55,
        sender: { id: 1 },
        conversation: conv,
        mediaUrl: null,
      };
      (messagesService as any).findByIdWithConversation = jest
        .fn()
        .mockResolvedValue(msg);
      (messagesService as any).deleteById = jest.fn().mockResolvedValue(true);

      await service.handleDeleteMessage(
        mockClient as any,
        { messageId: 55, mode: 'for_everyone' },
        mockServer as any,
        onlineUsers,
      );

      expect(conversationsService.clearPinnedMessage).toHaveBeenCalledWith(10);
      expect(mockClient.emit).toHaveBeenCalledWith(
        'messageUnpinned',
        { conversationId: 10 },
      );
    });
  });

  describe('handleGetMessages (H-01 IDOR guard)', () => {
    it('refuses a non-member: returns empty history and never queries messages', async () => {
      // Caller is user 1 (beforeEach). Conversation 10 is between users 2 and 3.
      conversationsService.findById.mockResolvedValue({
        id: 10,
        userOne: { id: 2 },
        userTwo: { id: 3 },
      } as Conversation);

      await service.handleGetMessages(mockClient as Socket, {
        conversationId: 10,
      });

      expect(messagesService.findByConversation).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('messageHistory', {
        conversationId: 10,
        messages: [],
      });
    });

    it('serves history to a participant', async () => {
      conversationsService.findById.mockResolvedValue({
        id: 10,
        userOne: { id: 1 },
        userTwo: { id: 2 },
      } as Conversation);
      messagesService.findByConversation.mockResolvedValue([]);

      await service.handleGetMessages(mockClient as Socket, {
        conversationId: 10,
      });

      expect(messagesService.findByConversation).toHaveBeenCalledWith(
        10,
        undefined,
        undefined,
        1,
      );
      expect(mockClient.emit).toHaveBeenCalledWith('messageHistory', {
        conversationId: 10,
        messages: [],
      });
    });
  });
});
