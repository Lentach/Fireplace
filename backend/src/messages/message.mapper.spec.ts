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
      disappearAfterSeconds: null,
      tempId: null,
      reactions: {},
    });
    expect(payload.createdAt).toBeDefined();
  });

  it('should parse stored reaction JSON into payload reactions', () => {
    const msg = createMockMessage({
      reactions: JSON.stringify({
        '👍': [10, 20],
        '🔥': [30],
      }),
    });
    const payload = MessageMapper.toPayload(msg);
    expect(payload.reactions).toEqual({
      '👍': [10, 20],
      '🔥': [30],
    });
  });

  it('does not throw and degrades to empty reactions on corrupt JSON', () => {
    const msg = createMockMessage({ reactions: '{not valid json' });
    expect(() => MessageMapper.toPayload(msg)).not.toThrow();
    expect(MessageMapper.toPayload(msg).reactions).toEqual({});
  });

  it('degrades to empty reactions when stored JSON is not an object', () => {
    const msg = createMockMessage({ reactions: '42' });
    expect(MessageMapper.toPayload(msg).reactions).toEqual({});
  });

  it('maps null reactions to an empty object', () => {
    const msg = createMockMessage({ reactions: null });
    expect(MessageMapper.toPayload(msg).reactions).toEqual({});
  });

  it('a corrupt reactions row does not blank sibling messages in a history response', () => {
    const corrupt = createMockMessage({ id: 1, reactions: '<<corrupt' });
    const healthy = createMockMessage({
      id: 2,
      reactions: JSON.stringify({ '👍': [7] }),
    });
    const history = [corrupt, healthy].map((msg) =>
      MessageMapper.toPayload(msg),
    );
    expect(history[0].reactions).toEqual({});
    expect(history[1].reactions).toEqual({ '👍': [7] });
  });

  it('should include link preview metadata for encrypted messages', () => {
    const msg = createMockMessage({
      content: '[encrypted]',
      encryptedContent: '3:base64ciphertext==',
      linkPreviewUrl: 'https://example.com/article',
      linkPreviewTitle: 'Example article',
      linkPreviewImageUrl: 'https://example.com/preview.png',
    });
    const payload = MessageMapper.toPayload(msg);
    expect(payload).toMatchObject({
      content: '[encrypted]',
      encryptedContent: '3:base64ciphertext==',
      linkPreviewUrl: 'https://example.com/article',
      linkPreviewTitle: 'Example article',
      linkPreviewImageUrl: 'https://example.com/preview.png',
    });
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

  // E2E all message types: encryptedContent short-circuits the reply preview
  // regardless of messageType — the server never reads messageType when the
  // replied-to message is encrypted.
  it.each([
    MessageType.VOICE,
    MessageType.IMAGE,
    MessageType.PING,
    MessageType.GIF,
    MessageType.FILE,
    MessageType.VIDEO,
  ])(
    'shows "Encrypted message" for encrypted %s reply-to (never a type label)',
    (messageType) => {
      const replyToMsg = {
        id: 50,
        content: '[encrypted]',
        encryptedContent: '3:cipher==',
        messageType,
        sender: { username: 'alice' },
      } as unknown as Message;
      const msg = createMockMessage({ replyTo: replyToMsg });
      const payload = MessageMapper.toPayload(msg);
      // mapper returns Record<string, unknown>; reply preview shape is known here
      const replyTo = payload.replyTo as { content: string };
      expect(replyTo.content).toBe('Encrypted message');
    },
  );

  it('should show type-specific labels for unencrypted reply-to', () => {
    const cases = [
      { messageType: MessageType.VOICE, expected: 'Voice message' },
      { messageType: MessageType.IMAGE, expected: 'Image' },
      { messageType: MessageType.PING, expected: 'Ping' },
      { messageType: MessageType.GIF, expected: 'GIF' },
      { messageType: MessageType.FILE, expected: 'File' },
      { messageType: MessageType.VIDEO, expected: 'Video' },
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

  it('truncates unencrypted TEXT reply preview to the first 150 chars', () => {
    const longContent = 'x'.repeat(300);
    const replyToMsg = {
      id: 70,
      content: longContent,
      encryptedContent: null,
      messageType: MessageType.TEXT,
      sender: { username: 'bob' },
    } as unknown as Message;
    const msg = createMockMessage({ replyTo: replyToMsg });
    const payload = MessageMapper.toPayload(msg);
    // mapper returns Record<string, unknown>; reply preview shape is known here
    const replyTo = payload.replyTo as { content: string };
    expect(replyTo.content).toBe(longContent.substring(0, 150));
    expect(replyTo.content).toHaveLength(150);
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

  it('should include disappearAfterSeconds in payload', () => {
    const msg = createMockMessage({ disappearAfterSeconds: 3600 });
    const payload = MessageMapper.toPayload(msg);
    expect(payload.disappearAfterSeconds).toBe(3600);
  });

  it('should format editedAt as ISO string when set', () => {
    const editedAt = new Date('2025-03-10T09:30:00Z');
    const msg = createMockMessage({ editedAt });
    const payload = MessageMapper.toPayload(msg);
    expect(payload.editedAt).toBe('2025-03-10T09:30:00.000Z');
  });

  it('should set editedAt to null when not set', () => {
    const msg = createMockMessage();
    const payload = MessageMapper.toPayload(msg);
    expect(payload.editedAt).toBeNull();
  });
});
