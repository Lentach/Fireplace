import { Message } from './message.entity';
import { DISAPPEARING_MAX_UNREAD_SECONDS } from './disappearing.constants';

/**
 * Effective expiry for display, history, unread counts, and cleanup.
 * - Grandfathered: expiresAt set at send.
 * - Read-mode after read: expiresAt set on markConversationRead.
 * - Read-mode never read: createdAt + DISAPPEARING_MAX_UNREAD_SECONDS.
 */
export function isMessageExpired(message: Message, now: Date = new Date()): boolean {
  const nowMs = now.getTime();

  if (message.expiresAt != null) {
    const expiresMs = new Date(message.expiresAt as Date).getTime();
    if (!Number.isNaN(expiresMs) && expiresMs <= nowMs) {
      return true;
    }
  }

  if (
    message.disappearAfterSeconds != null &&
    message.expiresAt == null
  ) {
    const createdMs = new Date(message.createdAt as Date).getTime();
    if (!Number.isNaN(createdMs)) {
      const unreadDeadlineMs =
        createdMs + DISAPPEARING_MAX_UNREAD_SECONDS * 1000;
      if (nowMs > unreadDeadlineMs) {
        return true;
      }
    }
  }

  return false;
}

/** SQL fragment: message row is NOT expired (for QueryBuilder alias `m`). */
export const MESSAGE_NOT_EXPIRED_SQL = `(
  (m."expiresAt" IS NOT NULL AND m."expiresAt" > CURRENT_TIMESTAMP)
  OR (
    m."disappearAfterSeconds" IS NOT NULL
    AND m."expiresAt" IS NULL
    AND m."createdAt" + INTERVAL '${DISAPPEARING_MAX_UNREAD_SECONDS} seconds' > CURRENT_TIMESTAMP
  )
  OR (
    m."expiresAt" IS NULL
    AND m."disappearAfterSeconds" IS NULL
  )
)`;
