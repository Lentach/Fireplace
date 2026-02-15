import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Message, MessageDeliveryStatus, MessageType } from './message.entity';
import { User } from '../users/user.entity';
import { Conversation } from '../conversations/conversation.entity';

@Injectable()
export class MessagesService {
  constructor(
    @InjectRepository(Message)
    private msgRepo: Repository<Message>,
  ) {}

  async create(
    content: string,
    sender: User,
    conversation: Conversation,
    options?: {
      deliveryStatus?: MessageDeliveryStatus;
      expiresAt?: Date | null;
      messageType?: MessageType;
      mediaUrl?: string | null;
      mediaDuration?: number | null;
    },
  ): Promise<Message> {
    const msg = this.msgRepo.create({
      content,
      sender,
      conversation,
      deliveryStatus: options?.deliveryStatus || MessageDeliveryStatus.SENT,
      expiresAt: options?.expiresAt || null,
      messageType: options?.messageType || MessageType.TEXT,
      mediaUrl: options?.mediaUrl || null,
      mediaDuration: options?.mediaDuration || null,
    });
    return this.msgRepo.save(msg);
  }

  // Get messages from a conversation with pagination support.
  // Fetches the N most recent messages (DESC), returns them oldest-first (ASC) for display.
  // offset=0: newest messages; offset=50: next 50 older messages.
  async findByConversation(
    conversationId: number,
    limit: number = 50,
    offset: number = 0,
  ): Promise<Message[]> {
    const messages = await this.msgRepo.find({
      where: { conversation: { id: conversationId } },
      relations: ['sender'],
      order: { createdAt: 'DESC' },
      take: limit,
      skip: offset,
    });
    return messages.reverse();
  }

  // Get the last (most recent) message from a conversation.
  // Returns null if no messages exist.
  async getLastMessage(conversationId: number): Promise<Message | null> {
    const message = await this.msgRepo.findOne({
      where: { conversation: { id: conversationId } },
      relations: ['sender'],
      order: { createdAt: 'DESC' },
    });
    return message || null;
  }

  /** Status order: never downgrade (e.g. READ must not become DELIVERED when events are processed out of order). */
  private static readonly DELIVERY_STATUS_ORDER: Record<MessageDeliveryStatus, number> = {
    [MessageDeliveryStatus.SENDING]: 0,
    [MessageDeliveryStatus.SENT]: 1,
    [MessageDeliveryStatus.DELIVERED]: 2,
    [MessageDeliveryStatus.READ]: 3,
  };

  async updateDeliveryStatus(
    messageId: number,
    status: MessageDeliveryStatus,
  ): Promise<Message | null> {
    const message = await this.msgRepo.findOne({
      where: { id: messageId },
      relations: ['sender', 'conversation'],
    });

    if (!message) {
      return null;
    }

    const currentOrder = MessagesService.DELIVERY_STATUS_ORDER[message.deliveryStatus];
    const newOrder = MessagesService.DELIVERY_STATUS_ORDER[status];
    if (newOrder <= currentOrder) {
      return message;
    }

    message.deliveryStatus = status;
    return this.msgRepo.save(message);
  }

  /**
   * Count unread messages for a recipient in a conversation.
   * Unread = messages sent by the other participant, not yet READ, not expired.
   */
  async countUnreadForRecipient(
    conversationId: number,
    recipientUserId: number,
  ): Promise<number> {
    const qb = this.msgRepo
      .createQueryBuilder('m')
      .innerJoin('m.sender', 's')
      .where('m.conversation_id = :convId', { convId: conversationId })
      .andWhere('s.id != :userId', { userId: recipientUserId })
      .andWhere('m."deliveryStatus" != :status', {
        status: MessageDeliveryStatus.READ,
      });
    // Exclude expired messages (column is deliveryStatus/expiresAt camelCase)
    qb.andWhere(
      '(m."expiresAt" IS NULL OR m."expiresAt" > CURRENT_TIMESTAMP)',
    );
    return qb.getCount();
  }

  /** Mark all messages in the conversation that were sent BY senderId (to the other participant) as READ. Returns updated messages with sender. */
  async markConversationAsReadFromSender(
    conversationId: number,
    senderId: number,
  ): Promise<Message[]> {
    const messages = await this.msgRepo.find({
      where: {
        conversation: { id: conversationId },
        sender: { id: senderId },
      },
      relations: ['sender', 'conversation'],
      order: { createdAt: 'ASC' },
    });
    const updated: Message[] = [];
    for (const m of messages) {
      if (m.deliveryStatus === MessageDeliveryStatus.READ) continue;
      m.deliveryStatus = MessageDeliveryStatus.READ;
      updated.push(await this.msgRepo.save(m));
    }
    return updated;
  }

  /**
   * Delete all messages in a conversation.
   * Used when clearing chat history.
   */
  async deleteAllByConversation(conversationId: number): Promise<void> {
    await this.msgRepo.delete({ conversation: { id: conversationId } });
  }
}
