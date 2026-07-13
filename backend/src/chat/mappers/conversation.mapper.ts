import { Conversation } from '../../conversations/conversation.entity';
import { UserMapper } from './user.mapper';
import { Message } from '../../messages/message.entity';
import { MessageMapper } from '../../messages/message.mapper';

export class ConversationMapper {
  static toPayload(
    conversation: Conversation,
    options?: {
      unreadCount?: number;
      lastMessage?: Message | null;
      pinnedMessage?: Message | null;
      muted?: boolean;
      mutedUntil?: Date | null;
    },
  ) {
    return {
      id: conversation.id,
      userOne: UserMapper.toPayload(conversation.userOne),
      userTwo: UserMapper.toPayload(conversation.userTwo),
      createdAt: conversation.createdAt,
      disappearingTimer: conversation.disappearingTimer,
      pinnedMessageId: conversation.pinnedMessageId ?? null,
      pinnedAt: conversation.pinnedAt ?? null,
      pinnedByUserId: conversation.pinnedByUserId ?? null,
      unreadCount: options?.unreadCount ?? 0,
      muted: options?.muted ?? false,
      mutedUntil: options?.mutedUntil ?? null,
      lastMessage: options?.lastMessage
        ? MessageMapper.toPayload(options.lastMessage, {
            conversationId: conversation.id,
          })
        : null,
      pinnedMessage: options?.pinnedMessage
        ? MessageMapper.toPayload(options.pinnedMessage, {
            conversationId: conversation.id,
          })
        : null,
    };
  }
}
