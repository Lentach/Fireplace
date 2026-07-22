import { ChatReactionService } from './chat-reaction.service';

describe('ChatReactionService', () => {
  let service: ChatReactionService;
  let mockMessagesService: any;
  let mockServer: any;
  let mockClient: any;
  let onlineUsers: Map<number, string>;

  const mockConversation = {
    id: 10,
    userOne: { id: 1 },
    userTwo: { id: 2 },
  };

  beforeEach(() => {
    mockMessagesService = {
      findByIdWithConversation: jest.fn(),
      addOrUpdateReaction: jest.fn(),
      removeReaction: jest.fn(),
    };
    service = new ChatReactionService(mockMessagesService);
    mockServer = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
    };
    mockClient = { data: { user: { id: 1 } }, emit: jest.fn() };
    onlineUsers = new Map([[2, 'socket-2']]);
  });

  describe('handleAddReaction', () => {
    it('should add reaction and emit to both parties', async () => {
      mockMessagesService.findByIdWithConversation.mockResolvedValue({
        id: 5,
        conversation: mockConversation,
      });
      mockMessagesService.addOrUpdateReaction.mockResolvedValue({
        id: 5,
        reactions: JSON.stringify({ '👍': [1] }),
      });

      await service.handleAddReaction(
        mockClient,
        { messageId: 5, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockMessagesService.addOrUpdateReaction).toHaveBeenCalledWith(5, 1, '👍');
      expect(mockClient.emit).toHaveBeenCalledWith('reactionUpdated', {
        messageId: 5,
        conversationId: 10,
        reactions: { '👍': [1] },
      });
      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('reactionUpdated', {
        messageId: 5,
        conversationId: 10,
        reactions: { '👍': [1] },
      });
    });

    it('should emit error on nonexistent message', async () => {
      mockMessagesService.findByIdWithConversation.mockResolvedValue(null);

      await service.handleAddReaction(
        mockClient,
        { messageId: 999, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', { message: 'Message not found' });
      expect(mockMessagesService.addOrUpdateReaction).not.toHaveBeenCalled();
    });

    it('should not proceed if no user on client', async () => {
      await service.handleAddReaction(
        { data: {} } as any,
        { messageId: 5, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockMessagesService.findByIdWithConversation).not.toHaveBeenCalled();
    });

    it('should emit error on invalid dto', async () => {
      await service.handleAddReaction(
        mockClient,
        { messageId: -1, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', expect.objectContaining({ message: expect.any(String) }));
    });

    it('should emit Unauthorized and not react when user is not a conversation participant', async () => {
      mockMessagesService.findByIdWithConversation.mockResolvedValue({
        id: 5,
        conversation: { id: 10, userOne: { id: 2 }, userTwo: { id: 3 } },
      });

      await service.handleAddReaction(
        mockClient,
        { messageId: 5, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', { message: 'Unauthorized' });
      expect(mockMessagesService.addOrUpdateReaction).not.toHaveBeenCalled();
    });
  });

  describe('handleRemoveReaction', () => {
    it('should remove reaction and emit to both parties', async () => {
      mockMessagesService.findByIdWithConversation.mockResolvedValue({
        id: 5,
        conversation: mockConversation,
      });
      mockMessagesService.removeReaction.mockResolvedValue({
        id: 5,
        reactions: JSON.stringify({}),
      });

      await service.handleRemoveReaction(
        mockClient,
        { messageId: 5, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockMessagesService.removeReaction).toHaveBeenCalledWith(5, 1, '👍');
      expect(mockClient.emit).toHaveBeenCalledWith('reactionUpdated', {
        messageId: 5,
        conversationId: 10,
        reactions: {},
      });
      expect(mockServer.to).toHaveBeenCalledWith('socket-2');
      expect(mockServer.emit).toHaveBeenCalledWith('reactionUpdated', {
        messageId: 5,
        conversationId: 10,
        reactions: {},
      });
    });

    it('should emit error on nonexistent message', async () => {
      mockMessagesService.findByIdWithConversation.mockResolvedValue(null);

      await service.handleRemoveReaction(
        mockClient,
        { messageId: 999, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', { message: 'Message not found' });
      expect(mockMessagesService.removeReaction).not.toHaveBeenCalled();
    });

    it('should not proceed if no user on client', async () => {
      await service.handleRemoveReaction(
        { data: {} } as any,
        { messageId: 5, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockMessagesService.findByIdWithConversation).not.toHaveBeenCalled();
    });

    it('should emit Unauthorized and not remove reaction when user is not a conversation participant', async () => {
      mockMessagesService.findByIdWithConversation.mockResolvedValue({
        id: 5,
        conversation: { id: 10, userOne: { id: 2 }, userTwo: { id: 3 } },
      });

      await service.handleRemoveReaction(
        mockClient,
        { messageId: 5, emoji: '👍' },
        mockServer,
        onlineUsers,
      );

      expect(mockClient.emit).toHaveBeenCalledWith('error', { message: 'Unauthorized' });
      expect(mockMessagesService.removeReaction).not.toHaveBeenCalled();
    });
  });
});
