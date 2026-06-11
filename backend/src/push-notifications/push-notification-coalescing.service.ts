import {
  Injectable,
  Logger,
  OnModuleDestroy,
} from '@nestjs/common';
import { PushNotificationsService } from './push-notifications.service';
import { MessagesService } from '../messages/messages.service';

/** Trailing debounce window before firing one push for a burst in the same chat. */
const DEBOUNCE_MS = 2500;
/** Upper bound so rapid sends cannot postpone notification indefinitely. */
const MAX_WAIT_MS = 10000;

interface PendingBucket {
  debounceTimer: NodeJS.Timeout;
  maxWaitTimer: NodeJS.Timeout;
  /** Display name of the message sender — shown as the notification title. */
  senderName?: string;
}

@Injectable()
export class PushNotificationCoalescingService implements OnModuleDestroy {
  private readonly logger = new Logger(PushNotificationCoalescingService.name);
  private readonly pending = new Map<string, PendingBucket>();

  constructor(
    private readonly pushNotificationsService: PushNotificationsService,
    private readonly messagesService: MessagesService,
  ) {}

  /**
   * Schedule a coalesced push for one message to recipientUserId in conversationId.
   * Multiple rapid messages collapse into a single notify with live unread counts.
   */
  scheduleMessagePush(
    recipientUserId: number,
    conversationId: number,
    senderName?: string,
  ): Promise<void> {
    const key = `${recipientUserId}:${conversationId}`;
    const existing = this.pending.get(key);

    if (existing) {
      clearTimeout(existing.debounceTimer);
      existing.debounceTimer = setTimeout(() => {
        void this.flush(key);
      }, DEBOUNCE_MS);
      if (senderName) existing.senderName = senderName;
      return Promise.resolve();
    }

    const bucket: PendingBucket = {
      debounceTimer: setTimeout(() => void this.flush(key), DEBOUNCE_MS),
      maxWaitTimer: setTimeout(() => void this.flush(key), MAX_WAIT_MS),
      senderName,
    };
    this.pending.set(key, bucket);
    return Promise.resolve();
  }

  private async flush(key: string): Promise<void> {
    const bucket = this.pending.get(key);
    if (!bucket) return;

    clearTimeout(bucket.debounceTimer);
    clearTimeout(bucket.maxWaitTimer);
    this.pending.delete(key);
    const senderName = bucket.senderName;

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

    let unreadCount: number | undefined;
    let unreadTotal: number | undefined;
    let unreadConversationIds: number[] | undefined;

    try {
      const summary = await this.messagesService.getUnreadSummaryForUser(recipientUserId);
      unreadTotal = summary.unreadTotal;
      unreadConversationIds = summary.unreadConversationIds;
      unreadCount = summary.countByConversationId.get(conversationId) ?? 0;
    } catch (err) {
      this.logger.warn(`Push coalesce: unread summary failed for userId=${recipientUserId}`, err);
    }

    await this.pushNotificationsService
      .notify(recipientUserId, {
        conversationId,
        unreadCount,
        unreadTotal,
        unreadConversationIds,
        senderName,
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
