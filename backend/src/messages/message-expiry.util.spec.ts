import { isMessageExpired } from './message-expiry.util';
import { DISAPPEARING_MAX_UNREAD_SECONDS } from './disappearing.constants';
import { Message } from './message.entity';

function expiryRow(partial: Partial<Message>): Message {
  return partial as Message;
}

describe('isMessageExpired', () => {
  const now = new Date('2026-05-17T12:00:00Z');

  it('returns true when expiresAt is in the past', () => {
    expect(
      isMessageExpired(
        expiryRow({
          expiresAt: new Date('2026-05-17T11:00:00Z'),
          createdAt: new Date('2026-05-16T12:00:00Z'),
        }),
        now,
      ),
    ).toBe(true);
  });

  it('returns false when expiresAt is in the future', () => {
    expect(
      isMessageExpired(
        expiryRow({
          expiresAt: new Date('2026-05-17T13:00:00Z'),
          createdAt: new Date('2026-05-16T12:00:00Z'),
        }),
        now,
      ),
    ).toBe(false);
  });

  it('returns true when expiresAt is exactly equal to now (<= boundary)', () => {
    expect(
      isMessageExpired(
        expiryRow({
          expiresAt: new Date(now.getTime()),
          createdAt: new Date('2026-05-16T12:00:00Z'),
        }),
        now,
      ),
    ).toBe(true);
  });

  it('returns false when both expiresAt and disappearAfterSeconds are null', () => {
    expect(
      isMessageExpired(
        expiryRow({
          expiresAt: null,
          disappearAfterSeconds: null,
          createdAt: new Date('2020-01-01T00:00:00Z'),
        }),
        now,
      ),
    ).toBe(false);
  });

  it('treats an invalid/NaN expiresAt as not-expired (NaN guard)', () => {
    expect(
      isMessageExpired(
        expiryRow({
          expiresAt: new Date('not-a-date'),
          disappearAfterSeconds: null,
          createdAt: new Date('2026-05-16T12:00:00Z'),
        }),
        now,
      ),
    ).toBe(false);
  });

  it('expires never-read read-mode message after 1 day from send', () => {
    const createdAt = new Date(
      now.getTime() - (DISAPPEARING_MAX_UNREAD_SECONDS + 60) * 1000,
    );
    expect(
      isMessageExpired(
        expiryRow({
          disappearAfterSeconds: 3600,
          expiresAt: null,
          createdAt,
        }),
        now,
      ),
    ).toBe(true);
  });

  it('keeps unread read-mode message within 1 day from send', () => {
    const createdAt = new Date(now.getTime() - 3600 * 1000);
    expect(
      isMessageExpired(
        expiryRow({
          disappearAfterSeconds: 86400,
          expiresAt: null,
          createdAt,
        }),
        now,
      ),
    ).toBe(false);
  });

  it('grandfathered send-time expiry unchanged when no disappearAfterSeconds', () => {
    expect(
      isMessageExpired(
        expiryRow({
          expiresAt: new Date('2026-05-17T13:00:00Z'),
          disappearAfterSeconds: null,
          createdAt: new Date('2026-05-10T12:00:00Z'),
        }),
        now,
      ),
    ).toBe(false);
  });
});
