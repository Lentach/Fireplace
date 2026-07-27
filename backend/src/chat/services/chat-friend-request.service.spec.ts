import { Test, TestingModule } from '@nestjs/testing';
import { ChatFriendRequestService } from './chat-friend-request.service';
import { FriendsService } from '../../friends/friends.service';
import { BlockedService } from '../../blocked/blocked.service';
import { UsersService } from '../../users/users.service';
import { ConversationsService } from '../../conversations/conversations.service';
import { MessagesService } from '../../messages/messages.service';
import { MediaCleanupService } from '../../media/media-cleanup.service';
import { ChatConversationService } from './chat-conversation.service';
import { Socket, Server } from 'socket.io';
import { FriendRequest, FriendRequestStatus } from '../../friends/friend-request.entity';
import { User } from '../../users/user.entity';

describe('ChatFriendRequestService', () => {
  let service: ChatFriendRequestService;
  let friendsService: jest.Mocked<FriendsService>;
  let blockedService: jest.Mocked<BlockedService>;
  let usersService: jest.Mocked<UsersService>;
  let conversationsService: jest.Mocked<ConversationsService>;
  let mockClient: Partial<Socket>;
  let mockServer: Partial<Server>;
  let onlineUsers: Map<number, string>;

  const mockSender = { id: 1, username: 'alice', tag: '0001' };
  const mockRecipient = { id: 2, username: 'bob', tag: '0002' };
  const mockFriendRequest = {
    id: 10,
    status: 'pending',
    sender: mockSender,
    receiver: mockRecipient,
  };

  beforeEach(async () => {
    mockClient = { data: { user: { id: 1 } }, emit: jest.fn() };
    mockServer = { to: jest.fn().mockReturnThis(), emit: jest.fn() };
    onlineUsers = new Map();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatFriendRequestService,
        {
          provide: FriendsService,
          useValue: {
            sendRequest: jest.fn(),
            acceptRequest: jest.fn(),
            rejectRequest: jest.fn(),
            unfriend: jest.fn(),
            getFriends: jest.fn().mockResolvedValue([]),
            getPendingRequests: jest.fn().mockResolvedValue([]),
            getSentRequests: jest.fn().mockResolvedValue([]),
            getPendingRequestCount: jest.fn().mockResolvedValue(0),
          },
        },
        {
          provide: BlockedService,
          useValue: {
            isBlocked: jest.fn().mockResolvedValue(false),
            getBlockedUserIds: jest.fn().mockResolvedValue([]),
            getBlockedByUserIds: jest.fn().mockResolvedValue([]),
          },
        },
        {
          provide: UsersService,
          useValue: {
            findById: jest.fn(),
            findByUsernameAndTag: jest.fn(),
          },
        },
        {
          provide: ConversationsService,
          useValue: {
            findOrCreate: jest.fn().mockResolvedValue({ id: 100 }),
            findByUser: jest.fn().mockResolvedValue([]),
            findByUsers: jest.fn().mockResolvedValue({ id: 50 }),
            delete: jest.fn().mockResolvedValue(undefined),
          },
        },
        {
          provide: MessagesService,
          useValue: {
            findMediaUrlsByConversation: jest.fn().mockResolvedValue([]),
          },
        },
        {
          provide: MediaCleanupService,
          useValue: {
            deleteMediaFile: jest.fn().mockResolvedValue(undefined),
          },
        },
        {
          provide: ChatConversationService,
          useValue: {
            conversationsWithUnread: jest.fn().mockResolvedValue([]),
          },
        },
      ],
    }).compile();

    service = module.get<ChatFriendRequestService>(ChatFriendRequestService);
    friendsService = module.get(FriendsService) as jest.Mocked<FriendsService>;
    blockedService = module.get(BlockedService) as jest.Mocked<BlockedService>;
    usersService = module.get(UsersService) as jest.Mocked<UsersService>;
    conversationsService = module.get(ConversationsService) as jest.Mocked<ConversationsService>;
  });

  describe('handleSendFriendRequest', () => {
    it('emits friendRequestSent when request is pending', async () => {
      usersService.findById
        .mockResolvedValueOnce(mockSender as any)
        .mockResolvedValueOnce(mockRecipient as any);
      friendsService.sendRequest.mockResolvedValue({
        ...mockFriendRequest,
        status: 'pending',
      } as any);

      await service.handleSendFriendRequest(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
        onlineUsers,
      );

      expect(friendsService.sendRequest).toHaveBeenCalledWith(mockSender, mockRecipient);
      expect(mockClient.emit).toHaveBeenCalledWith('friendRequestSent', expect.any(Object));
    });

    it('runs auto-accept flow when request is accepted (mutual)', async () => {
      usersService.findById
        .mockResolvedValueOnce(mockSender as any)
        .mockResolvedValueOnce(mockRecipient as any);
      friendsService.sendRequest.mockResolvedValue({
        ...mockFriendRequest,
        status: 'accepted',
      } as any);
      onlineUsers.set(2, 'socket-2');

      await service.handleSendFriendRequest(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('friendRequestAccepted', expect.any(Object));
      expect(conversationsService.findOrCreate).toHaveBeenCalledWith(mockSender, mockRecipient);
      expect(mockClient.emit).toHaveBeenCalledWith('openConversation', { conversationId: 100 });
    });

    it('emits error when recipient blocked sender', async () => {
      usersService.findById
        .mockResolvedValueOnce(mockSender as any)
        .mockResolvedValueOnce(mockRecipient as any);
      blockedService.isBlocked.mockResolvedValue(true);

      await service.handleSendFriendRequest(
        mockClient as any,
        { recipientId: 2 },
        mockServer as any,
        onlineUsers,
      );

      expect(friendsService.sendRequest).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'You are blocked by this user',
      });
    });

    it('emits error when sending to self', async () => {
      usersService.findById
        .mockResolvedValueOnce(mockSender as any)
        .mockResolvedValueOnce(mockSender as any);

      await service.handleSendFriendRequest(
        mockClient as any,
        { recipientId: 1 },
        mockServer as any,
        onlineUsers,
      );

      expect(friendsService.sendRequest).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'Cannot send friend request to yourself',
      });
    });

    it('emits error when user not found', async () => {
      usersService.findById.mockResolvedValueOnce(mockSender as any).mockResolvedValueOnce(null);

      await service.handleSendFriendRequest(
        mockClient as any,
        { recipientId: 999 },
        mockServer as any,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'User not found',
      });
    });
  });

  describe('handleAcceptFriendRequest', () => {
    it('emits friendRequestAccepted and creates conversation', async () => {
      friendsService.acceptRequest.mockResolvedValue({
        ...mockFriendRequest,
        sender: mockSender,
        receiver: mockRecipient,
      } as any);
      usersService.findById
        .mockResolvedValueOnce(mockSender as any)
        .mockResolvedValueOnce(mockRecipient as any);
      conversationsService.findOrCreate.mockResolvedValue({ id: 100 } as any);

      await service.handleAcceptFriendRequest(
        mockClient as any,
        { requestId: 10 },
        mockServer as any,
        onlineUsers,
      );

      expect(friendsService.acceptRequest).toHaveBeenCalledWith(10, 1);
      expect(mockClient.emit).toHaveBeenCalledWith('friendRequestAccepted', expect.any(Object));
      expect(conversationsService.findOrCreate).toHaveBeenCalled();
    });

    it('emits error when accept fails', async () => {
      friendsService.acceptRequest.mockRejectedValue(new Error('Request not found'));

      await service.handleAcceptFriendRequest(
        mockClient as any,
        { requestId: 999 },
        mockServer as any,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'Request not found',
      });
    });
  });

  describe('handleRejectFriendRequest', () => {
    it('emits friendRequestRejected and friendRequestsList', async () => {
      friendsService.rejectRequest.mockResolvedValue({
        ...mockFriendRequest,
        status: 'rejected',
      } as any);
      friendsService.getPendingRequests.mockResolvedValue([]);
      friendsService.getPendingRequestCount.mockResolvedValue(0);
      mockClient.data = { user: { id: 2 } };
      onlineUsers.set(1, 'socket-1');

      await service.handleRejectFriendRequest(
        mockClient as Socket,
        { requestId: 10 },
        mockServer as Server,
        onlineUsers,
      );


      expect(friendsService.rejectRequest).toHaveBeenCalledWith(10, 2);
      expect(mockClient.emit).toHaveBeenCalledWith('friendRequestRejected', expect.any(Object));
      expect(mockClient.emit).toHaveBeenCalledWith('friendRequestsList', []);
      expect(mockClient.emit).toHaveBeenCalledWith('sentRequestsList', []);
      expect(mockClient.emit).toHaveBeenCalledWith('pendingRequestsCount', { count: 0 });
      expect(mockServer.to).toHaveBeenCalledWith('socket-1');
      expect(mockServer.emit).toHaveBeenCalledWith('sentRequestsList', []);
    });
  });

  describe('handleGetFriendRequests', () => {
    it('emits mapped sent requests without changing the inbound pending count', async () => {
      const sentRequest = Object.assign(new FriendRequest(), {
        id: 11,
        status: FriendRequestStatus.PENDING,
        sender: Object.assign(new User(), mockSender),
        receiver: Object.assign(new User(), mockRecipient),
        createdAt: new Date('2026-07-27T10:00:00.000Z'),
        respondedAt: null,
      });
      friendsService.getSentRequests.mockResolvedValue([sentRequest]);
      friendsService.getPendingRequestCount.mockResolvedValue(7);

      await service.handleGetFriendRequests(mockClient as Socket);

      expect(mockClient.emit).toHaveBeenCalledWith('friendRequestsList', []);
      expect(mockClient.emit).toHaveBeenCalledWith('sentRequestsList', [
        expect.objectContaining({
          id: 11,
          sender: expect.objectContaining({
            id: 1,
            username: 'alice',
            tag: '0001',
            about: null,
            profilePhotos: [],
          }),
          receiver: expect.objectContaining({
            id: 2,
            username: 'bob',
            tag: '0002',
            about: null,
            profilePhotos: [],
          }),
          status: FriendRequestStatus.PENDING,
          createdAt: new Date('2026-07-27T10:00:00.000Z'),
          respondedAt: null,
        }),
      ]);
      expect(mockClient.emit).toHaveBeenCalledWith('pendingRequestsCount', {
        count: 7,
      });
      expect(friendsService.getPendingRequestCount).toHaveBeenCalledTimes(1);
    });
  });

  describe('handleUnfriend', () => {
    it('calls unfriend and emits unfriended', async () => {
      await service.handleUnfriend(
        mockClient as any,
        { userId: 2 },
        mockServer as any,
        onlineUsers,
      );

      expect(friendsService.unfriend).toHaveBeenCalledWith(1, 2);
      expect(conversationsService.findByUsers).toHaveBeenCalledWith(1, 2);
      expect(mockClient.emit).toHaveBeenCalledWith('unfriended', { userId: 1 });
    });

    it('broadcasts unfriended to the other user when online', async () => {
      onlineUsers.set(2, 'socket-2');

      await service.handleUnfriend(
        mockClient as any,
        { userId: 2 },
        mockServer as any,
        onlineUsers,
      );

      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('unfriended', { userId: 1 });
    });

    it('emits error when unfriend fails', async () => {
      friendsService.unfriend.mockRejectedValue(new Error('Not friends'));

      await service.handleUnfriend(
        mockClient as any,
        { userId: 2 },
        mockServer as any,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', {
        message: 'Not friends',
      });
    });
  });

  describe('handleGetFriends', () => {
    it('excludes blocked users from friendsList', async () => {
      const friend = { id: 2, username: 'bob', tag: '0002', profilePictureUrl: null };
      friendsService.getFriends.mockResolvedValue([friend] as any);
      blockedService.getBlockedUserIds.mockResolvedValue([2]);
      blockedService.getBlockedByUserIds.mockResolvedValue([]);

      await service.handleGetFriends(mockClient as any);

      expect(mockClient.emit).toHaveBeenCalledWith('friendsList', []);
    });

    it('emits mapped friend payload when no blocks', async () => {
      const friend = { id: 2, username: 'bob', tag: '0002', profilePictureUrl: null };
      friendsService.getFriends.mockResolvedValue([friend] as any);
      blockedService.getBlockedUserIds.mockResolvedValue([]);
      blockedService.getBlockedByUserIds.mockResolvedValue([]);

      await service.handleGetFriends(mockClient as any);

      expect(mockClient.emit).toHaveBeenCalledWith(
        'friendsList',
        expect.arrayContaining([
          expect.objectContaining({ id: 2, username: 'bob', tag: '0002' }),
        ]),
      );
    });
  });

});
