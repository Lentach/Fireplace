import { Conversation } from '../../conversations/conversation.entity';
import { UserMapper } from './user.mapper';
import { Message } from '../../messages/message.entity';
import { MessageMapper } from '../../messages/message.mapper';

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
        ? MessageMapper.toPayload(options.lastMessage, {
            conversationId: conversation.id,
          })
        : null,
    };
  }
}
