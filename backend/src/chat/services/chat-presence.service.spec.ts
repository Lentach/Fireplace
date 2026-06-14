import { ChatPresenceService } from './chat-presence.service';

describe('ChatPresenceService', () => {
  let service: ChatPresenceService;
  let mockServer: any;
  let mockClient: any;
  let onlineUsers: Map<number, string>;

  beforeEach(() => {
    service = new ChatPresenceService();
    mockServer = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
    };
    mockClient = { data: { user: { id: 1 } } };
    onlineUsers = new Map([[2, 'socket-2']]);
  });

  describe('handleTyping', () => {
    it('should emit partnerTyping to recipient', () => {
      service.handleTyping(
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

    it('should not emit if recipient offline', () => {
      service.handleTyping(
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

    it('should not emit if no user on client', () => {
      service.handleTyping(
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
  });

  describe('handleRecordingVoice', () => {
    it('should emit partnerRecordingVoice to recipient', () => {
      service.handleRecordingVoice(
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

    it('should not emit if recipient offline', () => {
      service.handleRecordingVoice(
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

    it('should not emit if no user on client', () => {
      service.handleRecordingVoice(
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
  });

  describe('handlePushClientState', () => {
    it('stores push prefs on client.data when valid (with freshness stamp)', () => {
      service.handlePushClientState(mockClient, {
        activeConversationId: 7,
        clientVisible: true,
      });

      expect(mockClient.data.pushClientState).toMatchObject({
        activeConversationId: 7,
        clientVisible: true,
      });
      expect(typeof mockClient.data.pushClientState.updatedAt).toBe('number');
    });

    it('allows null activeConversationId', () => {
      service.handlePushClientState(mockClient, {
        activeConversationId: null,
        clientVisible: false,
      });

      expect(mockClient.data.pushClientState).toMatchObject({
        activeConversationId: null,
        clientVisible: false,
      });
      expect(typeof mockClient.data.pushClientState.updatedAt).toBe('number');
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
