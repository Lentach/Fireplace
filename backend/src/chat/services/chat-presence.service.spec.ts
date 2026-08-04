import { ChatPresenceService } from './chat-presence.service';

describe('ChatPresenceService', () => {
  let service: ChatPresenceService;
  let mockBlockedService: any;
  let mockServer: any;
  let mockClient: any;
  let onlineUsers: Map<number, string>;

  beforeEach(() => {
    mockBlockedService = {
      isBlockedByEither: jest.fn().mockResolvedValue(false),
    };
    service = new ChatPresenceService(mockBlockedService);
    mockServer = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
    };
    mockClient = { data: { user: { id: 1 } } };
    onlineUsers = new Map([[2, 'socket-2']]);
  });

  describe('handleTyping', () => {
    it('should emit partnerTyping to recipient', async () => {
      await service.handleTyping(
        mockClient,
        {
          recipientId: 2,
          conversationId: 10,
        },
        mockServer,
        onlineUsers,
      );

      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('partnerTyping', {
        senderId: 1,
        conversationId: 10,
      });
    });

    it('should not emit if recipient offline', async () => {
      await service.handleTyping(
        mockClient,
        {
          recipientId: 99,
          conversationId: 10,
        },
        mockServer,
        onlineUsers,
      );

      expect(mockServer.to).not.toHaveBeenCalled();
    });

    it('should not emit if no user on client', async () => {
      await service.handleTyping(
        { data: {} } as any,
        {
          recipientId: 2,
          conversationId: 10,
        },
        mockServer,
        onlineUsers,
      );

      expect(mockServer.to).not.toHaveBeenCalled();
    });

    it('should not emit partnerTyping when either user has blocked the other', async () => {
      mockBlockedService.isBlockedByEither.mockResolvedValue(true);

      await service.handleTyping(
        mockClient,
        {
          recipientId: 2,
          conversationId: 10,
        },
        mockServer,
        onlineUsers,
      );

      expect(mockBlockedService.isBlockedByEither).toHaveBeenCalledWith(1, 2);
      expect(mockServer.to).not.toHaveBeenCalled();
      expect(mockServer.emit).not.toHaveBeenCalled();
    });

    it('should emit partnerTyping for the reverse direction when not blocked', async () => {
      const reverseClient = { data: { user: { id: 2 } } };
      const reverseOnline = new Map([[1, 'socket-1']]);

      await service.handleTyping(
        reverseClient as any,
        {
          recipientId: 1,
          conversationId: 10,
        },
        mockServer,
        reverseOnline,
      );

      expect(mockBlockedService.isBlockedByEither).toHaveBeenCalledWith(2, 1);
      expect(mockServer.to).toHaveBeenCalledWith('socket-1');
      expect(mockServer.emit).toHaveBeenCalledWith('partnerTyping', {
        senderId: 2,
        conversationId: 10,
      });
    });
  });

  describe('handleRecordingVoice', () => {
    it('should emit partnerRecordingVoice to recipient', async () => {
      await service.handleRecordingVoice(
        mockClient,
        {
          recipientId: 2,
          conversationId: 10,
          isRecording: true,
        },
        mockServer,
        onlineUsers,
      );

      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('partnerRecordingVoice', {
        senderId: 1,
        conversationId: 10,
        isRecording: true,
      });
    });

    it('should not emit if recipient offline', async () => {
      await service.handleRecordingVoice(
        mockClient,
        {
          recipientId: 99,
          conversationId: 10,
          isRecording: true,
        },
        mockServer,
        onlineUsers,
      );

      expect(mockServer.to).not.toHaveBeenCalled();
    });

    it('should not emit if no user on client', async () => {
      await service.handleRecordingVoice(
        { data: {} } as any,
        {
          recipientId: 2,
          conversationId: 10,
          isRecording: true,
        },
        mockServer,
        onlineUsers,
      );

      expect(mockServer.to).not.toHaveBeenCalled();
    });

    it('should not emit partnerRecordingVoice when either user has blocked the other', async () => {
      mockBlockedService.isBlockedByEither.mockResolvedValue(true);

      await service.handleRecordingVoice(
        mockClient,
        {
          recipientId: 2,
          conversationId: 10,
          isRecording: true,
        },
        mockServer,
        onlineUsers,
      );

      expect(mockBlockedService.isBlockedByEither).toHaveBeenCalledWith(1, 2);
      expect(mockServer.to).not.toHaveBeenCalled();
      expect(mockServer.emit).not.toHaveBeenCalled();
    });
  });

  describe('handlePushClientState', () => {
    it('stores push prefs on client.data when valid', () => {
      service.handlePushClientState(mockClient, {
        activeConversationId: 7,
        clientVisible: true,
      });

      expect(mockClient.data.pushClientState).toEqual({
        activeConversationId: 7,
        clientVisible: true,
      });
    });

    it('allows null activeConversationId', () => {
      service.handlePushClientState(mockClient, {
        activeConversationId: null,
        clientVisible: false,
      });

      expect(mockClient.data.pushClientState).toEqual({
        activeConversationId: null,
        clientVisible: false,
      });
    });

    it('no-op when payload invalid', () => {
      service.handlePushClientState(mockClient, {
        activeConversationId: -1,
        clientVisible: true,
      });

      expect(mockClient.data.pushClientState).toBeUndefined();
    });

    it('no-op when no user id', () => {
      const bare = { data: {} };
      service.handlePushClientState(bare as any, {
        activeConversationId: 1,
        clientVisible: true,
      });

      expect((bare as any).data.pushClientState).toBeUndefined();
    });
  });
});
