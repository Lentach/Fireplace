import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MediaCleanupService } from '../media/media-cleanup.service';
import { Message } from './message.entity';
import { DISAPPEARING_MAX_UNREAD_SECONDS } from './disappearing.constants';
import { isMessageExpired } from './message-expiry.util';

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
    const unreadCutoff = new Date(
      now.getTime() - DISAPPEARING_MAX_UNREAD_SECONDS * 1000,
    );

    const candidates = await this.messagesRepo
      .createQueryBuilder('m')
      .where('m."expiresAt" IS NOT NULL AND m."expiresAt" < :now', { now })
      .orWhere(
        `m."disappearAfterSeconds" IS NOT NULL AND m."expiresAt" IS NULL AND m."createdAt" < :unreadCutoff`,
        { unreadCutoff },
      )
      .getMany();

    const expiredMessages = candidates.filter((m) =>
      isMessageExpired(m, now),
    );

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
