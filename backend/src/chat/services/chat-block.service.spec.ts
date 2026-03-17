import { ChatBlockService } from './chat-block.service';

describe('ChatBlockService', () => {
  let service: ChatBlockService;
  let mockBlockedService: any;
  let mockServer: any;
  let mockClient: any;
  let onlineUsers: Map<number, string>;

  beforeEach(() => {
    mockBlockedService = {
      block: jest.fn(),
      unblock: jest.fn(),
      getBlockedUsers: jest.fn().mockResolvedValue([]),
    };
    service = new ChatBlockService(mockBlockedService);
    mockServer = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
    };
    mockClient = { data: { user: { id: 1 } }, emit: jest.fn() };
    onlineUsers = new Map([[2, 'socket-2']]);
  });

  describe('handleBlockUser', () => {
    it('should block user and emit blockedList + youWereBlocked', async () => {
      await service.handleBlockUser(mockClient, { userId: 2 }, mockServer, onlineUsers);
      expect(mockBlockedService.block).toHaveBeenCalledWith(1, 2);
      expect(mockClient.emit).toHaveBeenCalledWith('blockedList', []);
      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('youWereBlocked', { userId: 1 });
    });

    it('should reject self-block', async () => {
      await service.handleBlockUser(mockClient, { userId: 1 }, mockServer, onlineUsers);
      expect(mockBlockedService.block).not.toHaveBeenCalled();
      expect(mockClient.emit).toHaveBeenCalledWith('error', { message: 'Cannot block yourself' });
    });

    it('should not emit if no user on client', async () => {
      await service.handleBlockUser({ data: {} } as any, { userId: 2 }, mockServer, onlineUsers);
      expect(mockBlockedService.block).not.toHaveBeenCalled();
    });

    it('should not emit youWereBlocked if blocked user is offline', async () => {
      onlineUsers.clear();
      await service.handleBlockUser(mockClient, { userId: 2 }, mockServer, onlineUsers);
      expect(mockBlockedService.block).toHaveBeenCalledWith(1, 2);
      expect(mockClient.emit).toHaveBeenCalledWith('blockedList', []);
      expect(mockServer.to).not.toHaveBeenCalled();
    });

    it('should emit error on failure', async () => {
      mockBlockedService.block.mockRejectedValue(new Error('DB error'));
      await service.handleBlockUser(mockClient, { userId: 2 }, mockServer, onlineUsers);
      expect(mockClient.emit).toHaveBeenCalledWith('error', { message: 'DB error' });
    });
  });

  describe('handleUnblockUser', () => {
    it('should unblock and emit updated blockedList', async () => {
      await service.handleUnblockUser(mockClient, { userId: 2 });
      expect(mockBlockedService.unblock).toHaveBeenCalledWith(1, 2);
      expect(mockClient.emit).toHaveBeenCalledWith('blockedList', []);
    });

    it('should not emit if no user on client', async () => {
      await service.handleUnblockUser({ data: {} } as any, { userId: 2 });
      expect(mockBlockedService.unblock).not.toHaveBeenCalled();
    });

    it('should emit error on failure', async () => {
      mockBlockedService.unblock.mockRejectedValue(new Error('DB error'));
      await service.handleUnblockUser(mockClient, { userId: 2 });
      expect(mockClient.emit).toHaveBeenCalledWith('error', { message: 'DB error' });
    });
  });

  describe('handleGetBlockedList', () => {
    it('should emit blockedList', async () => {
      await service.handleGetBlockedList(mockClient);
      expect(mockBlockedService.getBlockedUsers).toHaveBeenCalledWith(1);
      expect(mockClient.emit).toHaveBeenCalledWith('blockedList', []);
    });

    it('should not emit if no user on client', async () => {
      await service.handleGetBlockedList({ data: {} } as any);
      expect(mockBlockedService.getBlockedUsers).not.toHaveBeenCalled();
    });
  });
});
