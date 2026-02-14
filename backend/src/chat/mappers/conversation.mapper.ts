import { Conversation } from '../../conversations/conversation.entity';
import { UserMapper } from './user.mapper';
import { Message } from '../../messages/message.entity';

export class ConversationMapper {
  static toPayload(
    conversation: Conversation,
    options?: { unreadCount?: number; lastMessage?: Message | null },
  ) {
    return {
      id: conversation.id,
      userOne: UserMapper.toPayload(conversation.userOne),
      userTwo: UserMapper.toPayload(conversation.userTwo),
      createdAt: conversation.createdAt,
      disappearingTimer: conversation.disappearingTimer,
      unreadCount: options?.unreadCount ?? 0,
      lastMessage: options?.lastMessage
        ? {
            id: options.lastMessage.id,
            content: options.lastMessage.content,
            senderId: options.lastMessage.sender?.id,
            senderEmail: options.lastMessage.sender?.email,
            senderUsername: options.lastMessage.sender?.username,
            conversationId: options.lastMessage.conversation?.id ?? conversation.id,
            createdAt: options.lastMessage.createdAt,
            deliveryStatus: options.lastMessage.deliveryStatus,
            expiresAt: options.lastMessage.expiresAt,
            messageType: options.lastMessage.messageType,
            mediaUrl: options.lastMessage.mediaUrl,
          }
        : null,
    };
  }

  static toPayloadArray(conversations: Conversation[]) {
    return conversations.map((c) => this.toPayload(c));
  }
}
