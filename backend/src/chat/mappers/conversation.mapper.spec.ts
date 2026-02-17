import { ConversationMapper } from './conversation.mapper';
import { Conversation } from '../../conversations/conversation.entity';
import { User } from '../../users/user.entity';
import { Message } from '../../messages/message.entity';

function createMockConversation(): Conversation {
  const userOne = { id: 1, email: 'a@x.com', username: 'alice', profilePictureUrl: null } as unknown as User;
  const userTwo = { id: 2, email: 'b@x.com', username: 'bob', profilePictureUrl: null } as unknown as User;
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
      disappearingTimer: 86400,
    });
    expect(payload.userOne).toEqual({ id: 1, email: 'a@x.com', username: 'alice', profilePictureUrl: null });
    expect(payload.userTwo).toEqual({ id: 2, email: 'b@x.com', username: 'bob', profilePictureUrl: null });
  });

  it('should include unreadCount and lastMessage when provided', () => {
    const conv = createMockConversation();
    const lastMsg = {
      id: 100,
      content: 'Hi',
      sender: { id: 1, email: 'a@x.com', username: 'alice', profilePictureUrl: null },
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
});
