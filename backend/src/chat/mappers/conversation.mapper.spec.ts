import { ConversationMapper } from './conversation.mapper';
import { Conversation } from '../../conversations/conversation.entity';
import { User } from '../../users/user.entity';
import { Message } from '../../messages/message.entity';

function createMockConversation(): Conversation {
  const userOne = { id: 1, username: 'alice', tag: '0427', profilePictureUrl: null } as unknown as User;
  const userTwo = { id: 2, username: 'bob', tag: '1234', profilePictureUrl: null } as unknown as User;
  return {
    id: 10,
    userOne,
    userTwo,
    createdAt: new Date('2025-01-10T10:00:00Z'),
    disappearingTimer: 86400,
  } as Conversation;
}

describe('ConversationMapper', () => {
  it('should map conversation to payload', () => {
    const conv = createMockConversation();
    const payload = ConversationMapper.toPayload(conv);
    expect(payload).toMatchObject({
      id: 10,
      unreadCount: 0,
      lastMessage: null,
      pinnedMessageId: null,
      pinnedAt: null,
      pinnedByUserId: null,
      pinnedMessage: null,
      disappearingTimer: 86400,
    });
    expect(payload.userOne).toEqual({
      id: 1,
      username: 'alice',
      tag: '0427',
      about: null,
      profilePictureUrl: null,
      profilePhotos: [],
    });
    expect(payload.userTwo).toEqual({
      id: 2,
      username: 'bob',
      tag: '1234',
      about: null,
      profilePictureUrl: null,
      profilePhotos: [],
    });
  });

  it('should include unreadCount and lastMessage when provided', () => {
    const conv = createMockConversation();
    const lastMsg = {
      id: 100,
      content: 'Hi',
      sender: { id: 1, username: 'alice', profilePictureUrl: null },
      conversation: { id: 10 },
      createdAt: new Date(),
      deliveryStatus: 'SENT',
      messageType: 'TEXT',
      mediaUrl: null,
      mediaDuration: null,
      expiresAt: null,
    } as unknown as Message;
    const payload = ConversationMapper.toPayload(conv, {
      unreadCount: 3,
      lastMessage: lastMsg,
    });
    expect(payload.unreadCount).toBe(3);
    expect(payload.lastMessage).toBeDefined();
    expect(payload.lastMessage?.id).toBe(100);
    expect(payload.lastMessage?.content).toBe('Hi');
  });

  it('should include pin metadata and map pinnedMessage with conversation id override', () => {
    const pinnedAt = new Date('2025-04-20T14:30:00Z');
    const conv = {
      ...createMockConversation(),
      pinnedMessageId: 200,
      pinnedAt,
      pinnedByUserId: 2,
    } as Conversation;
    const pinnedMessage = {
      id: 200,
      content: '[encrypted]',
      encryptedContent: '3:pinnedCiphertext==',
      sender: { id: 2, username: 'bob', profilePictureUrl: null },
      conversation: { id: 999 },
      createdAt: new Date('2025-04-20T14:00:00Z'),
      deliveryStatus: 'READ',
      messageType: 'TEXT',
      mediaUrl: null,
      mediaDuration: null,
      expiresAt: null,
    } as unknown as Message;
    const payload = ConversationMapper.toPayload(conv, { pinnedMessage });
    expect(payload.pinnedMessageId).toBe(200);
    expect(payload.pinnedAt).toBe(pinnedAt);
    expect(payload.pinnedByUserId).toBe(2);
    expect(payload.pinnedMessage).toMatchObject({
      id: 200,
      content: '[encrypted]',
      encryptedContent: '3:pinnedCiphertext==',
      conversationId: 10,
      senderId: 2,
      senderUsername: 'bob',
    });
  });
});
