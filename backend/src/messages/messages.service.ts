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
    });
    return this.msgRepo.save(msg);
  }

  // Get messages from a conversation with pagination support.
  // Returns messages ordered oldest first (ASC).
  async findByConversation(
    conversationId: number,
    limit: number = 50,
    offset: number = 0,
  ): Promise<Message[]> {
    return this.msgRepo.find({
      where: { conversation: { id: conversationId } },
      relations: ['sender'],
      order: { createdAt: 'ASC' },
      take: limit,
      skip: offset,
    });
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
}
