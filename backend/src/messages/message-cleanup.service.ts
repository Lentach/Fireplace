import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MediaCleanupService } from '../media/media-cleanup.service';
import { Message } from './message.entity';
import { DISAPPEARING_MAX_UNREAD_SECONDS } from './disappearing.constants';
import { isMessageExpired } from './message-expiry.util';

/**
 * Max messages hydrated + processed per DB round-trip. Bounds both memory and
 * the number of concurrent fs-unlinks fired per batch, so a large backlog can
 * never fan out an unbounded `Promise.all` of unlinks (OOM/EMFILE risk). Sized
 * to clear a realistic per-minute backlog in a handful of batches; the loop
 * keeps draining within a single tick while a full batch is returned, so it is
 * not throttled to one batch per minute.
 */
const CLEANUP_BATCH_SIZE = 500;

@Injectable()
export class MessageCleanupService {
  private readonly logger = new Logger(MessageCleanupService.name);

  /**
   * Re-entrancy guard. `@Cron(EVERY_MINUTE)` fires again even if the previous
   * invocation is still running — NestJS schedule does NOT serialise overlaps.
   * Without this, a backlog that takes >60s to drain would let tick T+60s
   * re-run the same not-yet-removed query and multiply unlink concurrency until
   * OOM/EMFILE. Reset in a `finally` so a thrown run cannot wedge the cron.
   */
  private isRunning = false;

  constructor(
    @InjectRepository(Message)
    private messagesRepo: Repository<Message>,
    private mediaCleanupService: MediaCleanupService,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async deleteExpiredMessages() {
    if (this.isRunning) {
      this.logger.warn(
        'Expiry cleanup still running from a previous tick — skipping this one',
      );
      return;
    }
    this.isRunning = true;
    try {
      const now = new Date();
      const unreadCutoff = new Date(
        now.getTime() - DISAPPEARING_MAX_UNREAD_SECONDS * 1000,
      );

      let totalDeleted = 0;
      // Batched drain: bound each round-trip with a LIMIT and keep looping
      // within this tick while a full batch comes back, so a backlog larger
      // than one batch still drains without waiting a minute per batch. Stop
      // as soon as a short batch arrives (nothing more to fetch) or a batch
      // yields no genuinely-expired rows (no forward progress possible —
      // avoids spinning on coarse-query rows that isMessageExpired rejects).
      for (;;) {
        const candidates = await this.messagesRepo
          .createQueryBuilder('m')
          .where('m."expiresAt" IS NOT NULL AND m."expiresAt" < :now', { now })
          .orWhere(
            `m."disappearAfterSeconds" IS NOT NULL AND m."expiresAt" IS NULL AND m."createdAt" < :unreadCutoff`,
            { unreadCutoff },
          )
          .take(CLEANUP_BATCH_SIZE)
          .getMany();

        if (candidates.length === 0) break;

        const expiredMessages = candidates.filter((m) =>
          isMessageExpired(m, now),
        );

        if (expiredMessages.length > 0) {
          await Promise.all(
            expiredMessages
              .map((message) => message.mediaUrl)
              .filter((mediaUrl): mediaUrl is string => !!mediaUrl)
              .map((mediaUrl) =>
                this.mediaCleanupService.deleteMediaFile(mediaUrl),
              ),
          );
          // Detach replies pointing at the doomed rows: the reply self-FK has
          // no ON DELETE clause, so removing a replied-to parent that expired
          // before its reply would throw 23503 and wedge this cron every
          // minute (media above already unlinked, rows never removed). Live
          // replies keep their content; only the preview link dies with the
          // parent. Runs BEFORE remove(), and media unlinks run before this.
          await this.messagesRepo.query(
            `UPDATE public.messages
           SET reply_to_message_id = NULL
         WHERE reply_to_message_id = ANY($1)`,
            [expiredMessages.map((m) => m.id)],
          );
          await this.messagesRepo.remove(expiredMessages);
          totalDeleted += expiredMessages.length;
        }

        // A short batch means the query is drained; no expired rows this batch
        // means the remaining candidates are not yet removable and re-querying
        // would loop forever, so stop and let the next tick retry.
        if (
          candidates.length < CLEANUP_BATCH_SIZE ||
          expiredMessages.length === 0
        ) {
          break;
        }
      }

      if (totalDeleted > 0) {
        this.logger.log(`Deleted ${totalDeleted} expired messages`);
      }
    } finally {
      this.isRunning = false;
    }
  }
}
