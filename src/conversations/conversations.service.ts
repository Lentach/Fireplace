import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Conversation } from './conversation.entity';
import { User } from '../users/user.entity';

@Injectable()
export class ConversationsService {
  constructor(
    @InjectRepository(Conversation)
    private convRepo: Repository<Conversation>,
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
    return this.convRepo.findOne({ where: { id } });
  }

  // All conversations for a given user
  async findByUser(userId: number): Promise<Conversation[]> {
    return this.convRepo.find({
      where: [
        { userOne: { id: userId } },
        { userTwo: { id: userId } },
      ],
    });
  }
}
