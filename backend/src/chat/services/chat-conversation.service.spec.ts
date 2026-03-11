import { Test, TestingModule } from '@nestjs/testing';
import { ChatConversationService } from './chat-conversation.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { UsersService } from '../../users/users.service';
import { BlockedService } from '../../blocked/blocked.service';
import { ChatValidationService } from './chat-validation.service';
import { Socket, Server } from 'socket.io';

describe('ChatConversationService', () => {
  let service: ChatConversationService;
  let chatValidationService: jest.Mocked<ChatValidationService>;
  let usersService: jest.Mocked<UsersService>;
  let conversationsService: jest.Mocked<ConversationsService>;
  let mockClient: Partial<Socket>;
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
          },
        },
        {
          provide: MessagesService,
          useValue: {
            countUnreadForRecipient: jest.fn().mockResolvedValue(0),
            getLastMessage: jest.fn().mockResolvedValue(null),
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
          useValue: { validateCanMessage: jest.fn().mockResolvedValue({ valid: true }) },
        },
      ],
    }).compile();

    service = module.get(ChatConversationService);
    chatValidationService = module.get(ChatValidationService) as jest.Mocked<ChatValidationService>;
    usersService = module.get(UsersService) as jest.Mocked<UsersService>;
    conversationsService = module.get(ConversationsService) as jest.Mocked<ConversationsService>;
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
        new Map(),
      );

      expect(chatValidationService.validateCanMessage).toHaveBeenCalledWith(1, 2);
      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        { message: 'You can only message friends' },
      );
      expect(conversationsService.findOrCreate).not.toHaveBeenCalled();
    });

    it('allows when users are friends', async () => {
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      chatValidationService.validateCanMessage.mockResolvedValue({ valid: true });
      conversationsService.findOrCreate.mockResolvedValue({ id: 10 } as any);

      await service.handleStartConversation(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
        new Map(),
      );

      expect(conversationsService.findOrCreate).toHaveBeenCalled();
    });
  });
});
