import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, LessThan } from 'typeorm';
import { Message } from './message.entity';

@Injectable()
export class MessageCleanupService {
  private readonly logger = new Logger(MessageCleanupService.name);

  constructor(
    @InjectRepository(Message)
    private messagesRepo: Repository<Message>,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async deleteExpiredMessages() {
    const now = new Date();

    const expiredMessages = await this.messagesRepo.find({
      where: {
        expiresAt: LessThan(now),
      },
    });

    if (expiredMessages.length > 0) {
      await this.messagesRepo.remove(expiredMessages);
      this.logger.log(`Deleted ${expiredMessages.length} expired messages`);
    }
  }
}
