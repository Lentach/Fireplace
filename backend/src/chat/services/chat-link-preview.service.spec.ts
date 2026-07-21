import { ChatLinkPreviewService } from './chat-link-preview.service';

describe('ChatLinkPreviewService', () => {
  let service: ChatLinkPreviewService;
  let mockMessagesService: any;
  let mockLinkPreviewService: any;
  let mockServer: any;
  let mockClient: any;

  beforeEach(() => {
    mockMessagesService = {
      updateLinkPreview: jest.fn(),
    };
    mockLinkPreviewService = {
      fetchPreview: jest.fn(),
    };
    service = new ChatLinkPreviewService(
      mockMessagesService,
      mockLinkPreviewService,
    );
    mockServer = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
    };
    mockClient = { emit: jest.fn() };
  });

  it('should fetch link preview and emit to both sender and recipient', async () => {
    const preview = {
      url: 'https://example.com',
      title: 'Example',
      imageUrl: 'https://example.com/img.png',
    };
    mockLinkPreviewService.fetchPreview.mockResolvedValue(preview);
    mockMessagesService.updateLinkPreview.mockResolvedValue(true);

    service.fetchAndEmitIfNeeded({
      content: 'Check out https://example.com',
      encryptedContent: null,
      messageType: 'TEXT',
      messageId: 42,
      conversationId: 10,
      client: mockClient,
      recipientSocketId: 'socket-2',
      server: mockServer,
    });

    // Allow the internal promise chain to resolve
    await new Promise((r) => process.nextTick(r));

    expect(mockLinkPreviewService.fetchPreview).toHaveBeenCalledWith(
      'Check out https://example.com',
    );
    expect(mockMessagesService.updateLinkPreview).toHaveBeenCalledWith(
      42,
      'https://example.com',
      'Example',
      'https://example.com/img.png',
    );
    const expectedPayload = {
      messageId: 42,
      conversationId: 10,
      linkPreviewUrl: 'https://example.com',
      linkPreviewTitle: 'Example',
      linkPreviewImageUrl: 'https://example.com/img.png',
    };
    expect(mockClient.emit).toHaveBeenCalledWith(
      'linkPreviewReady',
      expectedPayload,
    );
    expect(mockServer.to).toHaveBeenCalledWith('socket-2');
    expect(mockServer.emit).toHaveBeenCalledWith(
      'linkPreviewReady',
      expectedPayload,
    );
  });

  it('should skip when encryptedContent is present', async () => {
    service.fetchAndEmitIfNeeded({
      content: 'Check out https://example.com',
      encryptedContent: 'some-ciphertext',
      messageType: 'TEXT',
      messageId: 42,
      conversationId: 10,
      client: mockClient,
      recipientSocketId: 'socket-2',
      server: mockServer,
    });

    await new Promise((r) => process.nextTick(r));

    expect(mockLinkPreviewService.fetchPreview).not.toHaveBeenCalled();
    expect(mockClient.emit).not.toHaveBeenCalled();
  });

  it('should skip when messageType is not TEXT', async () => {
    service.fetchAndEmitIfNeeded({
      content: 'https://example.com',
      encryptedContent: null,
      messageType: 'IMAGE',
      messageId: 42,
      conversationId: 10,
      client: mockClient,
      recipientSocketId: undefined,
      server: mockServer,
    });

    await new Promise((r) => process.nextTick(r));

    expect(mockLinkPreviewService.fetchPreview).not.toHaveBeenCalled();
  });

  it('should handle link preview service failure gracefully', async () => {
    mockLinkPreviewService.fetchPreview.mockRejectedValue(
      new Error('Network error'),
    );

    service.fetchAndEmitIfNeeded({
      content: 'Check https://example.com',
      encryptedContent: null,
      messageType: 'TEXT',
      messageId: 42,
      conversationId: 10,
      client: mockClient,
      recipientSocketId: 'socket-2',
      server: mockServer,
    });

    // Should not throw — error is swallowed
    await new Promise((r) => process.nextTick(r));

    expect(mockClient.emit).not.toHaveBeenCalled();
    expect(mockMessagesService.updateLinkPreview).not.toHaveBeenCalled();
  });

  it('should skip emit when updateLinkPreview returns false', async () => {
    const preview = {
      url: 'https://example.com',
      title: 'Example',
      imageUrl: 'https://example.com/img.png',
    };
    mockLinkPreviewService.fetchPreview.mockResolvedValue(preview);
    mockMessagesService.updateLinkPreview.mockResolvedValue(false);

    service.fetchAndEmitIfNeeded({
      content: 'Check https://example.com',
      encryptedContent: null,
      messageType: 'TEXT',
      messageId: 42,
      conversationId: 10,
      client: mockClient,
      recipientSocketId: 'socket-2',
      server: mockServer,
    });

    await new Promise((r) => process.nextTick(r));

    expect(mockMessagesService.updateLinkPreview).toHaveBeenCalled();
    expect(mockClient.emit).not.toHaveBeenCalledWith(
      'linkPreviewReady',
      expect.anything(),
    );
    expect(mockServer.to).not.toHaveBeenCalled();
  });

  it('should not update or emit when fetchPreview resolves null', async () => {
    mockLinkPreviewService.fetchPreview.mockResolvedValue(null);

    service.fetchAndEmitIfNeeded({
      content: 'Check https://example.com',
      encryptedContent: null,
      messageType: 'TEXT',
      messageId: 42,
      conversationId: 10,
      client: mockClient,
      recipientSocketId: 'socket-2',
      server: mockServer,
    });

    await new Promise((r) => process.nextTick(r));

    expect(mockMessagesService.updateLinkPreview).not.toHaveBeenCalled();
    expect(mockClient.emit).not.toHaveBeenCalled();
  });

  it('should not emit to recipient when recipientSocketId is undefined', async () => {
    const preview = {
      url: 'https://example.com',
      title: 'Example',
      imageUrl: null,
    };
    mockLinkPreviewService.fetchPreview.mockResolvedValue(preview);
    mockMessagesService.updateLinkPreview.mockResolvedValue(true);

    service.fetchAndEmitIfNeeded({
      content: 'Check https://example.com',
      encryptedContent: null,
      messageType: 'TEXT',
      messageId: 42,
      conversationId: 10,
      client: mockClient,
      recipientSocketId: undefined,
      server: mockServer,
    });

    await new Promise((r) => process.nextTick(r));

    expect(mockClient.emit).toHaveBeenCalledWith('linkPreviewReady', expect.any(Object));
    expect(mockServer.to).not.toHaveBeenCalled();
  });
});
