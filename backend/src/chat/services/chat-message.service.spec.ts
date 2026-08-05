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
import { SERVED_MESSAGE_IDS_MAX_BATCH } from '../dto/served-message-ids.dto';

/**
 * Join a mock socket to a user room, mirroring the real adapter shape that
 * newestSocketForUser/emitToNewestTab read (see utils/user-room.ts): rooms is a
 * Map<roomKey, Set<socketId>> and sockets is a Map<socketId, Socket>. Set preserves
 * insertion order, so the LAST socket installed for a user is the newest tab.
 */
type MockSocket = { id: string; data: any; emit: jest.Mock };
function installSocket(
  server: any,
  userId: number,
  socketId: string,
  data: any = {},
): MockSocket {
  const s = (server.sockets ??= {
    adapter: { rooms: new Map() },
    sockets: new Map(),
  });
  s.adapter ??= { rooms: new Map() };
  s.adapter.rooms ??= new Map();
  s.sockets ??= new Map();
  const socket: MockSocket = { id: socketId, data, emit: jest.fn() };
  const roomKey = 'user:' + userId;
  let room: Set<string> | undefined = s.adapter.rooms.get(roomKey);
  if (!room) {
    room = new Set<string>();
    s.adapter.rooms.set(roomKey, room);
  }
  room.add(socketId);
  s.sockets.set(socketId, socket);
  return socket;
}

describe('ChatMessageService', () => {
  let service: ChatMessageService;
  let messagesService: jest.Mocked<MessagesService>;
  let conversationsService: jest.Mocked<ConversationsService>;
  let chatValidationService: jest.Mocked<ChatValidationService>;
  let usersService: jest.Mocked<UsersService>;
  let chatLinkPreviewService: jest.Mocked<ChatLinkPreviewService>;
  let pushCoalescingService: jest.Mocked<PushNotificationCoalescingService>;

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

  /**
   * Plain jest.fn handle for the served-ids lookup. Asserting through
   * `messagesService.findServedMessageIds` would reference a class-typed
   * method (unbound-method); the raw fn has no `this` to lose.
   */
  let findServedMessageIdsMock: jest.Mock;
  let mockClient: Partial<Socket>;
  let mockServer: Partial<Server>;

  beforeEach(async () => {
    findServedMessageIdsMock = jest.fn().mockResolvedValue([]);
    mockClient = {
      data: { user: { id: 1 } },
      emit: jest.fn(),
    };
    mockServer = { to: jest.fn().mockReturnThis(), emit: jest.fn() };

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
            findByIdWithConversation: jest.fn(),
            updateDeliveryStatus: jest.fn(),
            deleteById: jest.fn(),
            editMessage: jest.fn(),
            findServedMessageIds: findServedMessageIdsMock,
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
          useValue: {
            validateCanMessage: jest.fn().mockResolvedValue({ valid: true }),
          },
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
    chatLinkPreviewService = module.get(ChatLinkPreviewService);
    pushCoalescingService = module.get(PushNotificationCoalescingService);
    jest.clearAllMocks();
  });

  describe('handleSendMessage', () => {
    it('should reject non-allowlisted mediaUrl and emit error (no message created)', async () => {
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
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(
        mockConversation as Conversation,
      );
      messagesService.create.mockResolvedValue(mockMessage as Message);

      const data = {
        recipientId: 2,
        content: '',
        messageType: 'VOICE',
        mediaUrl:
          'https://res.cloudinary.com/demo/video/upload/v1/voice-messages/abc.m4a',
        mediaDuration: 5,
      };

      await service.handleSendMessage(
        mockClient as Socket,
        data,
        mockServer as Server,
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
      expect(mockClient.emit).toHaveBeenCalledWith(
        'messageSent',
        expect.any(Object),
      );
    });
    it('should not create message and emit error when validation rejects the send', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: false,
        error: 'blocked',
      });

      await service.handleSendMessage(
        mockClient as Socket,
        { recipientId: 2, content: 'hello' },
        mockServer as Server,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'blocked',
      });
      expect(messagesService.create).not.toHaveBeenCalled();
    });

    it('should pass encryptedContent to create and store [encrypted] as content', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(
        mockConversation as Conversation,
      );
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
      );

      expect(messagesService.create).toHaveBeenCalledWith(
        '[encrypted]',
        mockSender,
        mockConversation,
        expect.objectContaining({
          encryptedContent: '3:base64ciphertext==',
        }),
      );
      expect(mockClient.emit).toHaveBeenCalledWith(
        'messageSent',
        expect.any(Object),
      );
    });

    it('forwards encryptedContent to link-preview service', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(
        mockConversation as Conversation,
      );
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
      );

      // Forwarding contract: handleSendMessage passes encryptedContent through to
      // ChatLinkPreviewService (which owns the skip decision — covered in its own spec).
      expect(chatLinkPreviewService.fetchAndEmitIfNeeded).toHaveBeenCalledWith(
        expect.objectContaining({
          encryptedContent: '3:base64ciphertext==',
        }),
      );
    });

    const arrangeSuccessfulTextMessageSend = () => {
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(
        mockConversation as Conversation,
      );
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        content: 'hello',
        messageType: 'TEXT',
        mediaUrl: null,
        mediaDuration: null,
      } as Message);
    };

    const installRecipientSocket = (pushClientState: {
      clientVisible: boolean;
      activeConversationId: number | null;
    }) => installSocket(mockServer, 2, 'socket-bob', { pushClientState });

    it('does not schedule push when recipient is visible in the active conversation', async () => {
      arrangeSuccessfulTextMessageSend();
      const bob = installRecipientSocket({
        clientVisible: true,
        activeConversationId: 10,
      });

      await service.handleSendMessage(
        mockClient as Socket,
        { recipientId: 2, content: 'hello' },
        mockServer as Server,
      );

      expect(bob.emit).toHaveBeenCalledWith('newMessage', expect.anything());
      expect(pushCoalescingService.scheduleMessagePush).not.toHaveBeenCalled();
    });

    it.each([
      ['hidden', { clientVisible: false, activeConversationId: 10 }],
      [
        'active on another conversation',
        { clientVisible: true, activeConversationId: 11 },
      ],
    ])(
      'schedules push when recipient socket is online but %s',
      async (_caseName, pushClientState) => {
        arrangeSuccessfulTextMessageSend();
        const bob = installRecipientSocket(pushClientState);

        await service.handleSendMessage(
          mockClient as Socket,
          { recipientId: 2, content: 'hello' },
          mockServer as Server,
        );

        expect(bob.emit).toHaveBeenCalledWith('newMessage', expect.anything());
        expect(pushCoalescingService.scheduleMessagePush).toHaveBeenCalledWith(
          2,
          10,
          'alice',
        );
      },
    );

    it('does not suppress push when the focused tab is not the newest (BE-007 coherence)', async () => {
      arrangeSuccessfulTextMessageSend();
      // Older tab is visible+focused on the conversation; newer tab is not. Delivery
      // AND suppression both resolve to the newest tab, so the older focused tab must
      // not suppress the push — otherwise the message lands on a background tab while
      // the push is dropped and the user sees neither (a regression that was backed out).
      installSocket(mockServer, 2, 'sock-old', {
        pushClientState: { clientVisible: true, activeConversationId: 10 },
      });
      installSocket(mockServer, 2, 'sock-new', {
        pushClientState: { clientVisible: false, activeConversationId: 10 },
      });

      await service.handleSendMessage(
        mockClient as Socket,
        { recipientId: 2, content: 'hello' },
        mockServer as Server,
      );

      expect(pushCoalescingService.scheduleMessagePush).toHaveBeenCalledWith(
        2,
        10,
        'alice',
      );
    });
  });

  describe('E2E encrypted message types', () => {
    it('should store [encrypted] content and pass encryptedContent for PING', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(
        mockConversation as Conversation,
      );
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

    it.each([
      [
        'VOICE',
        '3:voiceCiphertext==',
        'http://localhost:3000/media/msgs/voice.bin',
      ],
      [
        'IMAGE',
        '3:imageCiphertext==',
        'http://localhost:3000/media/msgs/image.bin',
      ],
      [
        'GIF',
        '3:base64encryptedGifData',
        'http://localhost:3000/media/msgs/gif.bin',
      ],
      [
        'FILE',
        '3:base64encryptedFileData',
        'http://localhost:3000/media/msgs/file.bin',
      ],
    ])(
      'should persist mediaUrl and messageType for encrypted %s',
      async (messageType, encryptedContent, mediaUrl) => {
        chatValidationService.validateCanMessage.mockResolvedValue({
          valid: true,
        });
        usersService.findById
          .mockResolvedValueOnce(mockSender as User)
          .mockResolvedValueOnce(mockRecipient as User);
        conversationsService.findOrCreate.mockResolvedValue(
          mockConversation as Conversation,
        );
        messagesService.create.mockResolvedValue({
          ...mockMessage,
          content: '[encrypted]',
          encryptedContent,
          messageType,
          mediaUrl,
        } as Message);

        const data = {
          recipientId: 2,
          content: '[encrypted]',
          encryptedContent,
          messageType,
          mediaUrl,
        };

        await service.handleSendMessage(
          mockClient as Socket,
          data,
          mockServer as Server,
        );

        const opts = messagesService.create.mock.calls[0][3] as Record<
          string,
          unknown
        >;
        expect(opts.encryptedContent).toBe(encryptedContent);
        expect(opts.messageType).toBe(messageType);
        expect(opts.mediaUrl).toBe(mediaUrl);
      },
    );

    it('should emit messageSent and newMessage with encryptedContent for online recipient', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(
        mockConversation as Conversation,
      );

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

      const bob = installSocket(mockServer, 2, 'socket-bob');

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

      // newMessage to recipient (single newest tab via emitToNewestTab)
      expect(bob.emit).toHaveBeenCalledWith(
        'newMessage',
        expect.objectContaining({
          content: '[encrypted]',
          encryptedContent: '3:cipher==',
        }),
      );
    });

    it('delivers newMessage to exactly one (newest) tab and never via the user room', async () => {
      // Signal decryption is NOT idempotent: it consumes the message key and advances
      // the ratchet. Both tabs share one IndexedDB session, so fanning one ciphertext
      // to two tabs makes the second tab decrypt FAIL into the client's
      // session-destroying decryption-failure policy. newMessage MUST stay single-tab;
      // this test exists to stop anyone tidying it into a room emit.
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(
        mockConversation as Conversation,
      );
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        id: 200,
        content: '[encrypted]',
        encryptedContent: '3:cipher==',
        messageType: 'TEXT',
        mediaUrl: null,
        mediaDuration: null,
      } as Message);
      const older = installSocket(mockServer, 2, 'sock-old');
      const newer = installSocket(mockServer, 2, 'sock-new');

      await service.handleSendMessage(
        mockClient as Socket,
        {
          recipientId: 2,
          content: '[encrypted]',
          encryptedContent: '3:cipher==',
        },
        mockServer as Server,
      );

      // Exactly the newest tab receives it; the older tab does not; never room-fanned.
      expect(newer.emit).toHaveBeenCalledWith('newMessage', expect.anything());
      expect(older.emit).not.toHaveBeenCalledWith(
        'newMessage',
        expect.anything(),
      );
      expect(mockServer.to).not.toHaveBeenCalledWith('user:2');
    });
  });

  describe('read-based disappearing messages', () => {
    it('stores disappearAfterSeconds with null expiresAt on send', async () => {
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      usersService.findById
        .mockResolvedValueOnce(mockSender as User)
        .mockResolvedValueOnce(mockRecipient as User);
      conversationsService.findOrCreate.mockResolvedValue(
        mockConversation as Conversation,
      );
      messagesService.create.mockResolvedValue({
        ...mockMessage,
        disappearAfterSeconds: 300,
        expiresAt: null,
      } as Message);

      await service.handleSendMessage(
        mockClient as Socket,
        { recipientId: 2, content: 'hi', expiresIn: 300 },
        mockServer as Server,
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
      const toMock = jest.fn().mockReturnValue({ emit: jest.fn() });
      mockServer.to = toMock;

      mockClient.data = { user: { id: 1 } };

      await service.handleMarkConversationRead(
        mockClient as Socket,
        { conversationId: 10 },
        mockServer as Server,
      );

      expect(
        messagesService.markConversationAsReadFromSender,
      ).toHaveBeenCalledWith(10, 2);
      expect(toMock).toHaveBeenCalledWith('user:2');
      expect(toMock).toHaveBeenCalledWith('user:1');
      const emitCalls = toMock.mock.results.map((r) => r.value.emit.mock.calls);
      expect(
        emitCalls.some((calls) =>
          calls.some(
            (c) =>
              c[0] === 'messageDelivered' &&
              c[1].expiresAt === expiresAt.toISOString(),
          ),
        ),
      ).toBe(true);
    });
  });

  describe('handleMessageDelivered', () => {
    it('rejects when caller is the sender, not the recipient', async () => {
      // Message sender = userId 1 (the caller). Recipient = userId 2.
      const conv = { id: 10, userOne: { id: 1 }, userTwo: { id: 2 } };
      const msg = { id: 99, sender: { id: 1 }, conversation: conv };
      messagesService.findByIdWithConversation.mockResolvedValue(
        msg as Message,
      );
      messagesService.updateDeliveryStatus.mockResolvedValue(null);

      await service.handleMessageDelivered(
        mockClient as Socket,
        { messageId: 99 },
        mockServer as Server,
      );

      expect(messagesService.updateDeliveryStatus).not.toHaveBeenCalled();
    });

    it('allows when caller is the recipient', async () => {
      // Message sender = userId 2. Caller = userId 1 (recipient).
      const conv = { id: 10, userOne: { id: 2 }, userTwo: { id: 1 } };
      const updatedMsg = {
        id: 99,
        sender: { id: 2 },
        conversation: conv,
        deliveryStatus: 'DELIVERED',
      };
      messagesService.findByIdWithConversation.mockResolvedValue({
        id: 99,
        sender: { id: 2 },
        conversation: conv,
      } as Message);
      messagesService.updateDeliveryStatus.mockResolvedValue(
        updatedMsg as Message,
      );

      await service.handleMessageDelivered(
        mockClient as Socket,
        { messageId: 99 },
        mockServer as Server,
      );

      expect(messagesService.updateDeliveryStatus).toHaveBeenCalledWith(
        99,
        MessageDeliveryStatus.DELIVERED,
      );
    });

    it('room-addresses messageDelivered so every tab of the sender receives it (BE-007 multi-tab)', async () => {
      const conv = { id: 10, userOne: { id: 2 }, userTwo: { id: 1 } };
      messagesService.findByIdWithConversation.mockResolvedValue({
        id: 99,
        sender: { id: 2 },
        conversation: conv,
      } as Message);
      messagesService.updateDeliveryStatus.mockResolvedValue({
        id: 99,
        sender: { id: 2 },
        conversation: conv,
        deliveryStatus: 'DELIVERED',
      } as Message);
      // Sender (user 2) has TWO open tabs; both are joined to room user:2.
      installSocket(mockServer, 2, 'sock-2a');
      installSocket(mockServer, 2, 'sock-2b');

      await service.handleMessageDelivered(
        mockClient as Socket,
        { messageId: 99 },
        mockServer as Server,
      );

      // Room-addressed, not a single socket id: both tabs receive the receipt.
      expect(mockServer.to).toHaveBeenCalledWith('user:2');
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
      messagesService.findByIdWithConversation.mockResolvedValue(
        msg as Message,
      );
      messagesService.deleteById.mockResolvedValue(msg as Message);

      await service.handleDeleteMessage(
        mockClient as Socket,
        { messageId: 55, mode: 'for_everyone' },
        mockServer as Server,
      );

      expect(conversationsService.clearPinnedMessage).toHaveBeenCalledWith(10);
      expect(mockClient.emit).toHaveBeenCalledWith('messageUnpinned', {
        conversationId: 10,
      });
    });
  });

  describe('handleEditMessage', () => {
    it('updates the row and emits messageEdited to both sockets when sender edits within the window', async () => {
      const conv = { id: 10, userOne: { id: 1 }, userTwo: { id: 2 } };
      const msg = {
        id: 100,
        sender: { id: 1 },
        conversation: conv,
        createdAt: new Date(),
        messageType: 'TEXT',
      } as unknown as Message;
      const editedAt = new Date('2026-06-22T12:00:00Z');
      messagesService.findByIdWithConversation.mockResolvedValue(msg);
      messagesService.editMessage.mockResolvedValue({
        id: 100,
        editedAt,
      } as Message);
      const bob = installSocket(mockServer, 2, 'sock-bob');

      await service.handleEditMessage(
        mockClient as Socket,
        {
          messageId: 100,
          content: '[encrypted]',
          encryptedContent: 'new-cipher',
        },
        mockServer as Server,
      );

      expect(messagesService.editMessage).toHaveBeenCalledWith(100, 1, {
        encryptedContent: 'new-cipher',
        content: '[encrypted]',
      });
      const expectedPayload = {
        messageId: 100,
        conversationId: 10,
        content: '[encrypted]',
        encryptedContent: 'new-cipher',
        editedAt: '2026-06-22T12:00:00.000Z',
      };
      expect(mockClient.emit).toHaveBeenCalledWith(
        'messageEdited',
        expectedPayload,
      );
      expect(bob.emit).toHaveBeenCalledWith('messageEdited', expectedPayload);
    });

    it('emits editMessageFailed with reason not_sender when caller is not the sender', async () => {
      const conv = { id: 10, userOne: { id: 1 }, userTwo: { id: 2 } };
      const msg = {
        id: 100,
        sender: { id: 2 },
        conversation: conv,
        createdAt: new Date(),
      } as unknown as Message;
      messagesService.findByIdWithConversation.mockResolvedValue(msg);
      messagesService.editMessage.mockResolvedValue(null);

      await service.handleEditMessage(
        mockClient as Socket,
        {
          messageId: 100,
          content: '[encrypted]',
          encryptedContent: 'new-cipher',
        },
        mockServer as Server,
      );

      expect(messagesService.editMessage).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('editMessageFailed', {
        messageId: 100,
        reason: 'not_sender',
      });
    });

    it('emits editMessageFailed with reason window_expired when the edit window has passed', async () => {
      const conv = { id: 10, userOne: { id: 1 }, userTwo: { id: 2 } };
      const msg = {
        id: 100,
        sender: { id: 1 },
        conversation: conv,
        createdAt: new Date(Date.now() - 16 * 60 * 1000),
      } as unknown as Message;
      messagesService.findByIdWithConversation.mockResolvedValue(msg);
      messagesService.editMessage.mockResolvedValue(null);

      await service.handleEditMessage(
        mockClient as Socket,
        {
          messageId: 100,
          content: '[encrypted]',
          encryptedContent: 'new-cipher',
        },
        mockServer as Server,
      );

      expect(messagesService.editMessage).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('editMessageFailed', {
        messageId: 100,
        reason: 'window_expired',
      });
    });

    it('emits editMessageFailed with reason not_found when the message does not exist', async () => {
      messagesService.findByIdWithConversation.mockResolvedValue(null);
      messagesService.editMessage.mockResolvedValue(null);

      await service.handleEditMessage(
        mockClient as Socket,
        {
          messageId: 100,
          content: '[encrypted]',
          encryptedContent: 'new-cipher',
        },
        mockServer as Server,
      );

      expect(messagesService.editMessage).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('editMessageFailed', {
        messageId: 100,
        reason: 'not_found',
      });
    });

    it('emits editMessageFailed with reason not_text for a non-TEXT message', async () => {
      const conv = { id: 10, userOne: { id: 1 }, userTwo: { id: 2 } };
      const msg = {
        id: 100,
        sender: { id: 1 },
        conversation: conv,
        createdAt: new Date(),
        messageType: 'IMAGE',
      } as unknown as Message;
      messagesService.findByIdWithConversation.mockResolvedValue(msg);
      messagesService.editMessage.mockResolvedValue(null);

      await service.handleEditMessage(
        mockClient as Socket,
        {
          messageId: 100,
          content: '[encrypted]',
          encryptedContent: 'new-cipher',
        },
        mockServer as Server,
      );

      expect(messagesService.editMessage).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('editMessageFailed', {
        messageId: 100,
        reason: 'not_text',
      });
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

  describe('handleGetServedMessageIds', () => {
    /** Names of every event emitted to the caller in this test. */
    const emitted = () =>
      ((mockClient.emit as jest.Mock).mock.calls as unknown[][]).map((c) =>
        String(c[0]),
      );

    it('echoes the requestId with the ids the server still serves', async () => {
      findServedMessageIdsMock.mockResolvedValue([2, 4]);

      await service.handleGetServedMessageIds(mockClient as Socket, {
        requestId: 'abc',
        messageIds: [1, 2, 3, 4],
      });

      expect(findServedMessageIdsMock).toHaveBeenCalledWith([1, 2, 3, 4], 1);
      expect(mockClient.emit).toHaveBeenCalledWith('servedMessageIds', {
        requestId: 'abc',
        messageIds: [2, 4],
      });
    });

    it('answers a fully deleted history with an empty list', async () => {
      // Not an error case: the client is meant to destroy all of them.
      findServedMessageIdsMock.mockResolvedValue([]);

      await service.handleGetServedMessageIds(mockClient as Socket, {
        requestId: 'abc',
        messageIds: [1, 2],
      });

      expect(mockClient.emit).toHaveBeenCalledWith('servedMessageIds', {
        requestId: 'abc',
        messageIds: [],
      });
    });

    it('stays SILENT when the lookup throws', async () => {
      // The empty list above is an instruction to destroy plaintext, so a
      // database failure must never be able to manufacture one. No reply at
      // all leaves the client holding everything until the next attempt.
      findServedMessageIdsMock.mockRejectedValue(new Error('db down'));

      await service.handleGetServedMessageIds(mockClient as Socket, {
        requestId: 'abc',
        messageIds: [1, 2],
      });

      expect(emitted()).not.toContain('servedMessageIds');
    });

    it('rejects a malformed batch without answering it', async () => {
      await service.handleGetServedMessageIds(mockClient as Socket, {
        requestId: 'abc',
        messageIds: ['nope'],
      });

      expect(findServedMessageIdsMock).not.toHaveBeenCalled();
      expect(emitted()).toEqual(['error']);
    });

    it('rejects a batch over the size cap', async () => {
      await service.handleGetServedMessageIds(mockClient as Socket, {
        requestId: 'abc',
        messageIds: Array.from(
          { length: SERVED_MESSAGE_IDS_MAX_BATCH + 1 },
          (_, i) => i + 1,
        ),
      });

      expect(findServedMessageIdsMock).not.toHaveBeenCalled();
      expect(emitted()).toEqual(['error']);
    });

    it('ignores an unauthenticated socket', async () => {
      const anonymous: Partial<Socket> = { data: {}, emit: jest.fn() };

      await service.handleGetServedMessageIds(anonymous as Socket, {
        requestId: 'abc',
        messageIds: [1],
      });

      expect(findServedMessageIdsMock).not.toHaveBeenCalled();
      expect(anonymous.emit).not.toHaveBeenCalled();
    });
  });
});
