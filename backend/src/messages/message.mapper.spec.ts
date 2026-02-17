import { MessageMapper } from './message.mapper';
import { Message, MessageDeliveryStatus, MessageType } from './message.entity';
import { User } from '../users/user.entity';

function createMockMessage(overrides: Partial<Message> = {}): Message {
  return {
    id: 1,
    content: 'Hello',
    sender: {
      id: 10,
      email: 'sender@example.com',
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
      senderEmail: 'sender@example.com',
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
});
