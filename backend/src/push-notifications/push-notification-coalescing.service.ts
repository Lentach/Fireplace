import {
  Injectable,
  Logger,
  OnModuleDestroy,
} from '@nestjs/common';
import { PushNotificationsService } from './push-notifications.service';

/** Trailing debounce window before firing one push for a burst in the same chat. */
const DEBOUNCE_MS = 2500;
/** Upper bound so rapid sends cannot postpone notification indefinitely. */
const MAX_WAIT_MS = 10000;

interface PendingBucket {
  count: number;
  debounceTimer: NodeJS.Timeout;
  maxWaitTimer: NodeJS.Timeout;
}

@Injectable()
export class PushNotificationCoalescingService implements OnModuleDestroy {
  private readonly logger = new Logger(PushNotificationCoalescingService.name);
  private readonly pending = new Map<string, PendingBucket>();

  constructor(private readonly pushNotificationsService: PushNotificationsService) {}

  /**
   * Schedule a coalesced push for one message to recipientUserId in conversationId.
   * Multiple rapid messages collapse into a single notify with aggregated messageCount.
   */
  scheduleMessagePush(
    recipientUserId: number,
    conversationId: number,
  ): Promise<void> {
    const key = `${recipientUserId}:${conversationId}`;
    const existing = this.pending.get(key);

    if (existing) {
      existing.count += 1;
      clearTimeout(existing.debounceTimer);
      existing.debounceTimer = setTimeout(() => {
        this.flush(key);
      }, DEBOUNCE_MS);
      return Promise.resolve();
    }

    const bucket: PendingBucket = {
      count: 1,
      debounceTimer: setTimeout(() => this.flush(key), DEBOUNCE_MS),
      maxWaitTimer: setTimeout(() => this.flush(key), MAX_WAIT_MS),
    };
    this.pending.set(key, bucket);
    return Promise.resolve();
  }

  private flush(key: string): void {
    const bucket = this.pending.get(key);
    if (!bucket) return;

    clearTimeout(bucket.debounceTimer);
    clearTimeout(bucket.maxWaitTimer);
    this.pending.delete(key);

    const colon = key.indexOf(':');
    const recipientUserId = Number(key.slice(0, colon));
    const conversationId = Number(key.slice(colon + 1));

    if (
      !Number.isFinite(recipientUserId) ||
      !Number.isFinite(conversationId)
    ) {
      this.logger.warn(`Push coalesce flush skipped: invalid key ${key}`);
      return;
    }

    void this.pushNotificationsService
      .notify(recipientUserId, {
        conversationId,
      })
      .catch(() => {});
  }

  onModuleDestroy(): void {
    for (const bucket of this.pending.values()) {
      clearTimeout(bucket.debounceTimer);
      clearTimeout(bucket.maxWaitTimer);
    }
    this.pending.clear();
  }
}
