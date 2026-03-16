import { MessageMapper } from './message.mapper';
import { Message, MessageDeliveryStatus, MessageType } from './message.entity';
import { User } from '../users/user.entity';

function createMockMessage(overrides: Partial<Message> = {}): Message {
  return {
    id: 1,
    content: 'Hello',
    sender: {
      id: 10,
      username: 'sender',
      profilePictureUrl: null,
    } as unknown as User,
    conversation: { id: 5 } as any,
    createdAt: new Date('2025-01-15T12:00:00Z'),
    deliveryStatus: MessageDeliveryStatus.SENT,
    messageType: MessageType.TEXT,
    mediaUrl: null,
    mediaDuration: null,
    expiresAt: null,
    ...overrides,
  } as Message;
}

describe('MessageMapper', () => {
  it('should map message to payload', () => {
    const msg = createMockMessage();
    const payload = MessageMapper.toPayload(msg);
    expect(payload).toMatchObject({
      id: 1,
      content: 'Hello',
      senderId: 10,
      senderUsername: 'sender',
      conversationId: 5,
      deliveryStatus: 'SENT',
      messageType: 'TEXT',
      mediaUrl: null,
      mediaDuration: null,
      expiresAt: null,
      tempId: null,
    });
    expect(payload.createdAt).toBeDefined();
  });

  it('should use options.conversationId when provided', () => {
    const msg = createMockMessage();
    const payload = MessageMapper.toPayload(msg, { conversationId: 99 });
    expect(payload.conversationId).toBe(99);
  });

  it('should include tempId when provided', () => {
    const msg = createMockMessage();
    const payload = MessageMapper.toPayload(msg, { tempId: 'client-123' });
    expect(payload.tempId).toBe('client-123');
  });

  it('should format expiresAt as ISO string', () => {
    const expiresAt = new Date('2025-02-20T18:00:00Z');
    const msg = createMockMessage({ expiresAt });
    const payload = MessageMapper.toPayload(msg);
    expect(payload.expiresAt).toBe('2025-02-20T18:00:00.000Z');
  });

  it('should use "Encrypted message" for replyTo when replied-to message has encryptedContent', () => {
    const replyToMsg = {
      id: 42,
      content: '[encrypted]',
      encryptedContent: '2:base64ciphertext...',
      messageType: MessageType.TEXT,
      sender: { username: 'bob' },
    } as unknown as Message;
    const msg = createMockMessage({
      replyTo: replyToMsg,
    });
    const payload = MessageMapper.toPayload(msg);
    expect(payload.replyTo).toMatchObject({
      id: 42,
      content: 'Encrypted message',
      senderUsername: 'bob',
      messageType: 'TEXT',
    });
  });

  // --- E2E all message types: reply-to preview tests ---

  it('should show "Encrypted message" for encrypted VOICE reply-to (not "Voice message")', () => {
    const replyToMsg = {
      id: 50,
      content: '[encrypted]',
      encryptedContent: '3:voiceCipher==',
      messageType: MessageType.VOICE,
      sender: { username: 'alice' },
    } as unknown as Message;
    const msg = createMockMessage({ replyTo: replyToMsg });
    const payload = MessageMapper.toPayload(msg);
    // encryptedContent takes priority — server can't know it's voice
    expect((payload.replyTo as any).content).toBe('Encrypted message');
  });

  it('should show "Encrypted message" for encrypted IMAGE reply-to', () => {
    const replyToMsg = {
      id: 51,
      content: '[encrypted]',
      encryptedContent: '3:imageCipher==',
      messageType: MessageType.IMAGE,
      sender: { username: 'alice' },
    } as unknown as Message;
    const msg = createMockMessage({ replyTo: replyToMsg });
    const payload = MessageMapper.toPayload(msg);
    expect((payload.replyTo as any).content).toBe('Encrypted message');
  });

  it('should show "Encrypted message" for encrypted PING reply-to', () => {
    const replyToMsg = {
      id: 52,
      content: '[encrypted]',
      encryptedContent: '3:pingCipher==',
      messageType: MessageType.PING,
      sender: { username: 'alice' },
    } as unknown as Message;
    const msg = createMockMessage({ replyTo: replyToMsg });
    const payload = MessageMapper.toPayload(msg);
    expect((payload.replyTo as any).content).toBe('Encrypted message');
  });

  it('should show type-specific labels for unencrypted reply-to', () => {
    const cases = [
      { messageType: MessageType.VOICE, expected: 'Voice message' },
      { messageType: MessageType.IMAGE, expected: 'Image' },
      { messageType: MessageType.PING, expected: 'Ping' },
      { messageType: MessageType.GIF, expected: 'GIF' },
      { messageType: MessageType.FILE, expected: 'File' },
    ];
    for (const { messageType, expected } of cases) {
      const replyToMsg = {
        id: 60,
        content: '',
        encryptedContent: null,
        messageType,
        sender: { username: 'bob' },
      } as unknown as Message;
      const msg = createMockMessage({ replyTo: replyToMsg });
      const payload = MessageMapper.toPayload(msg);
      expect((payload.replyTo as any).content).toBe(expected);
    }
  });

  it('should show GIF label for GIF replyTo', () => {
    const baseMock = {
      id: 1,
      content: '',
      encryptedContent: null,
      sender: { username: 'bob' },
    };
    const msg = {
      ...createMockMessage(),
      messageType: MessageType.GIF,
      mediaUrl: 'https://res.cloudinary.com/demo/image/upload/v1/gif.gif',
      replyTo: {
        ...baseMock,
        id: 50,
        messageType: MessageType.GIF,
        mediaUrl: 'https://res.cloudinary.com/demo/image/upload/v1/gif2.gif',
      },
    };
    const payload = MessageMapper.toPayload(msg as any);
    expect((payload.replyTo as any).content).toBe('GIF');
  });

  it('should include encryptedContent in payload when present', () => {
    const msg = createMockMessage({
      content: '[encrypted]',
      encryptedContent: '3:base64data==',
    });
    const payload = MessageMapper.toPayload(msg);
    expect(payload.encryptedContent).toBe('3:base64data==');
    expect(payload.content).toBe('[encrypted]');
  });

  it('should set encryptedContent to null when not present', () => {
    const msg = createMockMessage();
    const payload = MessageMapper.toPayload(msg);
    expect(payload.encryptedContent).toBeNull();
  });
});
