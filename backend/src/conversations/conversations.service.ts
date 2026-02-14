import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Conversation } from './conversation.entity';
import { User } from '../users/user.entity';
import { Message } from '../messages/message.entity';

@Injectable()
export class ConversationsService {
  constructor(
    @InjectRepository(Conversation)
    private convRepo: Repository<Conversation>,
    @InjectRepository(Message)
    private messageRepo: Repository<Message>,
  ) {}

  // Find an existing conversation between two users.
  // If none exists — create a new one. This prevents duplicates.
  async findOrCreate(userOne: User, userTwo: User): Promise<Conversation> {
    const existing = await this.convRepo.findOne({
      where: [
        { userOne: { id: userOne.id }, userTwo: { id: userTwo.id } },
        { userOne: { id: userTwo.id }, userTwo: { id: userOne.id } },
      ],
    });

    if (existing) return existing;

    const conv = this.convRepo.create({ userOne, userTwo });
    return this.convRepo.save(conv);
  }

  async findById(id: number): Promise<Conversation | null> {
    return this.convRepo.findOne({
      where: { id },
      relations: ['userOne', 'userTwo'],
    });
  }

  // All conversations for a given user
  async findByUser(userId: number): Promise<Conversation[]> {
    return this.convRepo.find({
      where: [{ userOne: { id: userId } }, { userTwo: { id: userId } }],
      relations: ['userOne', 'userTwo'],
    });
  }

  // Find conversation between two specific users
  async findByUsers(
    userId1: number,
    userId2: number,
  ): Promise<Conversation | null> {
    return this.convRepo.findOne({
      where: [
        { userOne: { id: userId1 }, userTwo: { id: userId2 } },
        { userOne: { id: userId2 }, userTwo: { id: userId1 } },
      ],
    });
  }

  async delete(id: number): Promise<void> {
    // Delete messages first (no cascade configured)
    await this.messageRepo.delete({ conversation: { id } });
    await this.convRepo.delete({ id });
  }

  async updateDisappearingTimer(
    conversationId: number,
    seconds: number | null,
  ): Promise<Conversation | null> {
    const conversation = await this.findById(conversationId);
    if (!conversation) return null;

    conversation.disappearingTimer = seconds;
    return this.convRepo.save(conversation);
  }
}
