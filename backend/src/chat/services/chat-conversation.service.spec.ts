import { Test, TestingModule } from '@nestjs/testing';
import { ChatConversationService } from './chat-conversation.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { UsersService } from '../../users/users.service';
import { BlockedService } from '../../blocked/blocked.service';
import { ChatValidationService } from './chat-validation.service';
import { MediaCleanupService } from '../../media/media-cleanup.service';
import { ConversationNotificationPreferencesService } from '../../conversation-notification-preferences/conversation-notification-preferences.service';
import { Socket, Server } from 'socket.io';

describe('ChatConversationService', () => {
  let service: ChatConversationService;
  let chatValidationService: jest.Mocked<ChatValidationService>;
  let usersService: jest.Mocked<UsersService>;
  let conversationsService: jest.Mocked<ConversationsService>;
  let messagesService: jest.Mocked<MessagesService>;
  let mockClient: Partial<Socket>;
  let notificationPreferences: jest.Mocked<ConversationNotificationPreferencesService>;
  let mockServer: Partial<Server>;

  beforeEach(async () => {
    mockClient = { data: { user: { id: 1 } }, emit: jest.fn() };
    mockServer = { to: jest.fn().mockReturnThis(), emit: jest.fn() };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatConversationService,
        {
          provide: ConversationsService,
          useValue: {
            findOrCreate: jest.fn(),
            findByUser: jest.fn().mockResolvedValue([]),
            findById: jest.fn(),
            setPinnedMessage: jest.fn(),
            clearPinnedMessage: jest.fn(),
          },
        },
        {
          provide: MessagesService,
          useValue: {
            countUnreadForRecipient: jest.fn().mockResolvedValue(0),
            getLastMessage: jest.fn().mockResolvedValue(null),
            findMediaUrlsByConversation: jest.fn().mockResolvedValue([]),
            findByIdWithConversation: jest.fn(),
          },
        },
        { provide: UsersService, useValue: { findById: jest.fn() } },
        {
          provide: BlockedService,
          useValue: {
            getBlockedUserIds: jest.fn().mockResolvedValue([]),
            getBlockedByUserIds: jest.fn().mockResolvedValue([]),
          },
        },
        {
          provide: ChatValidationService,
          useValue: {
            validateCanMessage: jest.fn().mockResolvedValue({ valid: true }),
          },
        },
        {
          provide: MediaCleanupService,
          useValue: {
            deleteMediaFile: jest.fn().mockResolvedValue(undefined),
          },
        },
        {
          provide: ConversationNotificationPreferencesService,
          useValue: { setMute: jest.fn() },
        },
      ],
    }).compile();

    service = module.get(ChatConversationService);
    chatValidationService = module.get(
      ChatValidationService,
    ) as jest.Mocked<ChatValidationService>;
    usersService = module.get(UsersService) as jest.Mocked<UsersService>;
    conversationsService = module.get(
      ConversationsService,
    ) as jest.Mocked<ConversationsService>;
    messagesService = module.get(
      MessagesService,
    ) as jest.Mocked<MessagesService>;
    notificationPreferences = module.get(
      ConversationNotificationPreferencesService,
    ) as jest.Mocked<ConversationNotificationPreferencesService>;
  });

  describe('handleStartConversation', () => {
    it('rejects when users are not friends', async () => {
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: false,
        error: 'You can only message friends',
      });

      await service.handleStartConversation(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
      );

      expect(chatValidationService.validateCanMessage).toHaveBeenCalledWith(
        1,
        2,
      );
      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'You can only message friends',
      });
      expect(conversationsService.findOrCreate).not.toHaveBeenCalled();
    });

    it('allows when users are friends', async () => {
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      conversationsService.findOrCreate.mockResolvedValue({ id: 10 } as any);

      await service.handleStartConversation(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
      );

      expect(conversationsService.findOrCreate).toHaveBeenCalled();
    });
  });

  describe('handlePinMessage', () => {
    const conv = {
      id: 10,
      userOne: { id: 1 },
      userTwo: { id: 2 },
    };
    const msgA = {
      id: 100,
      content: 'a',
      conversation: conv,
      createdAt: new Date(),
      expiresAt: null,
      disappearAfterSeconds: null,
    };
    const msgB = {
      id: 101,
      content: 'b',
      conversation: conv,
      createdAt: new Date(),
      expiresAt: null,
      disappearAfterSeconds: null,
    };

    beforeEach(() => {
      conversationsService.findById.mockResolvedValue(conv as any);
      conversationsService.setPinnedMessage.mockImplementation(
        async (_cid, messageId, userId) =>
          ({
            id: 10,
            pinnedMessageId: messageId,
            pinnedAt: new Date(),
            pinnedByUserId: userId,
          }) as any,
      );
    });

    it('pins message B after message A (replace pin)', async () => {
      messagesService.findByIdWithConversation
        .mockResolvedValueOnce(msgA as any)
        .mockResolvedValueOnce(msgB as any);

      await service.handlePinMessage(
        mockClient as any,
        { conversationId: 10, messageId: 100 },
        mockServer as any,
      );
      await service.handlePinMessage(
        mockClient as any,
        { conversationId: 10, messageId: 101 },
        mockServer as any,
      );

      expect(conversationsService.setPinnedMessage).toHaveBeenNthCalledWith(
        1,
        10,
        100,
        1,
      );
      expect(conversationsService.setPinnedMessage).toHaveBeenLastCalledWith(
        10,
        101,
        1,
      );
      expect(mockClient.emit).toHaveBeenCalledWith(
        'messagePinned',
        expect.objectContaining({ pinnedMessageId: 100 }),
      );
      expect(mockClient.emit).toHaveBeenCalledWith(
        'messagePinned',
        expect.objectContaining({ pinnedMessageId: 101 }),
      );
    });

    it('rejects pin when message belongs to a different conversation', async () => {
      const foreignMsg = {
        id: 100,
        content: 'foreign',
        conversation: { id: 999, userOne: { id: 1 }, userTwo: { id: 2 } },
        createdAt: new Date(),
        expiresAt: null,
        disappearAfterSeconds: null,
      };
      messagesService.findByIdWithConversation.mockResolvedValue(
        foreignMsg as any,
      );

      await service.handlePinMessage(
        mockClient as any,
        { conversationId: 10, messageId: 100 },
        mockServer as any,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'Message not in conversation',
      });
      expect(conversationsService.setPinnedMessage).not.toHaveBeenCalled();
    });

    it('rejects pin from non-member', async () => {
      mockClient = { data: { user: { id: 99 } }, emit: jest.fn() };
      conversationsService.findById.mockResolvedValue(conv as any);

      await service.handlePinMessage(
        mockClient as any,
        { conversationId: 10, messageId: 100 },
        mockServer as any,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'Unauthorized',
      });
      expect(conversationsService.setPinnedMessage).not.toHaveBeenCalled();
    });

    it('rejects pin on expired message', async () => {
      const expiredMsg = {
        id: 100,
        content: 'expired',
        conversation: conv,
        createdAt: new Date('2020-01-01'),
        expiresAt: new Date('2020-01-02'),
        disappearAfterSeconds: null,
      };
      messagesService.findByIdWithConversation.mockResolvedValue(
        expiredMsg as any,
      );

      await service.handlePinMessage(
        mockClient as any,
        { conversationId: 10, messageId: 100 },
        mockServer as any,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'Cannot pin expired message',
      });
      expect(conversationsService.setPinnedMessage).not.toHaveBeenCalled();
    });
  });
  describe('handleSetConversationMute', () => {
    it('rejects a mute request from a non-member', async () => {
      conversationsService.findById.mockResolvedValue({
        id: 10,
        userOne: { id: 2 },
        userTwo: { id: 3 },
      } as never);

      await service.handleSetConversationMute(mockClient as unknown as Socket, {
        conversationId: 10,
        duration: '8h',
      });

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'Unauthorized',
      });
      expect(notificationPreferences.setMute).not.toHaveBeenCalled();
    });

    it('stores an allowed viewer-private duration and emits only to that viewer', async () => {
      conversationsService.findById.mockResolvedValue({
        id: 10,
        userOne: { id: 1 },
        userTwo: { id: 2 },
      } as never);
      notificationPreferences.setMute.mockResolvedValue({
        muted: true,
        until: new Date('2026-07-13T10:00:00.000Z'),
      });

      await service.handleSetConversationMute(mockClient as unknown as Socket, {
        conversationId: 10,
        duration: '8h',
      });

      expect(notificationPreferences.setMute).toHaveBeenCalledWith(1, 10, '8h');
      expect(mockClient.emit).toHaveBeenCalledWith('conversationMuteUpdated', {
        conversationId: 10,
        muted: true,
        mutedUntil: new Date('2026-07-13T10:00:00.000Z'),
      });
    });
  });

  describe('BE-007 multi-tab realtime delivery', () => {
    // A per-user room whose membership set has TWO socket ids models a user
    // with two tabs open. Addressing the room (not one socket id) is what the
    // BE-007 fix guarantees: both tabs receive the event.
    const onlineServer = (userId: number, socketIds: string[]) =>
      ({
        to: jest.fn().mockReturnThis(),
        emit: jest.fn(),
        sockets: {
          adapter: { rooms: new Map([[`user:${userId}`, new Set(socketIds)]]) },
          sockets: new Map(),
        },
      }) as unknown as Server;

    it('delivers startConversation conversationsList to the recipient room, reaching every tab', async () => {
      const server = onlineServer(2, ['tab-a', 'tab-b']);
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      conversationsService.findOrCreate.mockResolvedValue({ id: 10 } as any);

      await service.handleStartConversation(
        mockClient as any,
        { recipientId: 2 },
        server as any,
      );

      // Targets the room, not a socket id — a second tab would also receive.
      expect(server.to).toHaveBeenCalledWith('user:2');
      expect(server.to).not.toHaveBeenCalledWith('tab-a');
    });

    it('does NOT build the recipient conversations list when the recipient is offline', async () => {
      const server = onlineServer(999, []); // recipient 2 is absent -> offline
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      chatValidationService.validateCanMessage.mockResolvedValue({
        valid: true,
      });
      conversationsService.findOrCreate.mockResolvedValue({ id: 10 } as any);

      await service.handleStartConversation(
        mockClient as any,
        { recipientId: 2 },
        server as any,
      );

      // Expensive build stays guarded: no conversations fetched for the offline peer.
      expect(conversationsService.findByUser).not.toHaveBeenCalledWith(2);
      expect(server.to).not.toHaveBeenCalledWith('user:2');
    });

    it('delivers messagePinned to the peer room, reaching every tab', async () => {
      const server = onlineServer(2, ['tab-a', 'tab-b']);
      const conv = { id: 10, userOne: { id: 1 }, userTwo: { id: 2 } };
      conversationsService.findById.mockResolvedValue(conv as any);
      conversationsService.setPinnedMessage.mockResolvedValue({
        id: 10,
        pinnedMessageId: 100,
        pinnedAt: new Date(),
        pinnedByUserId: 1,
      } as any);
      messagesService.findByIdWithConversation.mockResolvedValue({
        id: 100,
        content: 'a',
        conversation: conv,
        createdAt: new Date(),
        expiresAt: null,
        disappearAfterSeconds: null,
      } as any);

      await service.handlePinMessage(
        mockClient as any,
        { conversationId: 10, messageId: 100 },
        server as any,
      );

      expect(server.to).toHaveBeenCalledWith('user:2');
      expect(server.to).not.toHaveBeenCalledWith('tab-a');
    });
  });
});
