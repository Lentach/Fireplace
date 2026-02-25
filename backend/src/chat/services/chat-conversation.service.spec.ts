import { Test, TestingModule } from '@nestjs/testing';
import { ChatConversationService } from './chat-conversation.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { UsersService } from '../../users/users.service';
import { FriendsService } from '../../friends/friends.service';
import { BlockedService } from '../../blocked/blocked.service';
import { Socket, Server } from 'socket.io';

describe('ChatConversationService', () => {
  let service: ChatConversationService;
  let friendsService: jest.Mocked<FriendsService>;
  let blockedService: jest.Mocked<BlockedService>;
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
        { provide: FriendsService, useValue: { areFriends: jest.fn() } },
        { provide: BlockedService, useValue: { isBlockedByEither: jest.fn() } },
      ],
    }).compile();

    service = module.get(ChatConversationService);
    friendsService = module.get(FriendsService) as jest.Mocked<FriendsService>;
    blockedService = module.get(BlockedService) as jest.Mocked<BlockedService>;
    usersService = module.get(UsersService) as jest.Mocked<UsersService>;
    conversationsService = module.get(ConversationsService) as jest.Mocked<ConversationsService>;
  });

  describe('handleStartConversation', () => {
    it('rejects when users are not friends', async () => {
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      blockedService.isBlockedByEither.mockResolvedValue(false);
      friendsService.areFriends.mockResolvedValue(false);

      await service.handleStartConversation(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
        new Map(),
      );

      expect(friendsService.areFriends).toHaveBeenCalledWith(1, 2);
      expect(mockClient.emit).toHaveBeenCalledWith(
        'error',
        { message: 'You can only start conversations with friends' },
      );
      expect(conversationsService.findOrCreate).not.toHaveBeenCalled();
    });

    it('allows when users are friends', async () => {
      usersService.findById
        .mockResolvedValueOnce({ id: 1, username: 'alice' } as any)
        .mockResolvedValueOnce({ id: 2, username: 'bob' } as any);
      blockedService.isBlockedByEither.mockResolvedValue(false);
      friendsService.areFriends.mockResolvedValue(true);
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
