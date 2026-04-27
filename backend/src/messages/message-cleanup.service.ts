import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, LessThan } from 'typeorm';
import { MediaCleanupService } from '../media/media-cleanup.service';
import { Message } from './message.entity';

@Injectable()
export class MessageCleanupService {
  private readonly logger = new Logger(MessageCleanupService.name);

  constructor(
    @InjectRepository(Message)
    private messagesRepo: Repository<Message>,
    private mediaCleanupService: MediaCleanupService,
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
      await Promise.all(
        expiredMessages
          .map((message) => message.mediaUrl)
          .filter((mediaUrl): mediaUrl is string => !!mediaUrl)
          .map((mediaUrl) => this.mediaCleanupService.deleteMediaFile(mediaUrl)),
      );
      await this.messagesRepo.remove(expiredMessages);
      this.logger.log(`Deleted ${expiredMessages.length} expired messages`);
    }
  }
}
