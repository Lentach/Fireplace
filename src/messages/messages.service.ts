import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Message } from './message.entity';
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
  ): Promise<Message> {
    const msg = this.msgRepo.create({ content, sender, conversation });
    return this.msgRepo.save(msg);
  }

  // Last 50 messages in a conversation, oldest first.
  // Simplified: no pagination in the MVP.
  async findByConversation(conversationId: number): Promise<Message[]> {
    return this.msgRepo.find({
      where: { conversation: { id: conversationId } },
      order: { createdAt: 'ASC' },
      take: 50,
    });
  }
}
