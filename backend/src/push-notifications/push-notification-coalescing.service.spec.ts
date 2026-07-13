import { Test, TestingModule } from '@nestjs/testing';
import { PushNotificationCoalescingService } from './push-notification-coalescing.service';
import { PushNotificationsService } from './push-notifications.service';
import { MessagesService } from '../messages/messages.service';
import { ConversationNotificationPreferencesService } from '../conversation-notification-preferences/conversation-notification-preferences.service';

describe('PushNotificationCoalescingService', () => {
  let service: PushNotificationCoalescingService;
  let notify: jest.Mock;
  let getUnreadSummary: jest.Mock;

  let isMuted: jest.Mock;
  const makeUnreadSummary = (convId: number, convCount: number, total: number) => ({
    unreadTotal: total,
    unreadConversationIds: [convId],
    countByConversationId: new Map([[convId, convCount]]),
  });

  beforeEach(async () => {
    jest.useFakeTimers();
    notify = jest.fn().mockResolvedValue(undefined);
    getUnreadSummary = jest.fn().mockResolvedValue(makeUnreadSummary(10, 3, 3));
    isMuted = jest.fn().mockResolvedValue(false);

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PushNotificationCoalescingService,
        { provide: PushNotificationsService, useValue: { notify } },
        { provide: MessagesService, useValue: { getUnreadSummaryForUser: getUnreadSummary } },
        {
          provide: ConversationNotificationPreferencesService,
          useValue: { isMuted },
        },
      ],
    }).compile();

    service = module.get(PushNotificationCoalescingService);
  });

  afterEach(() => {
    service.onModuleDestroy();
    jest.useRealTimers();
  });

  it('aggregates bursts into one notify after debounce', async () => {
    getUnreadSummary.mockResolvedValue(makeUnreadSummary(10, 3, 3));
    await service.scheduleMessagePush(2, 10);
    await service.scheduleMessagePush(2, 10);
    await service.scheduleMessagePush(2, 10);
    expect(notify).not.toHaveBeenCalled();

    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();

    expect(notify).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenCalledWith(2, {
      conversationId: 10,
      unreadCount: 3,
      unreadTotal: 3,
      unreadConversationIds: [10],
    });
  });

  it('flushes by max wait when debounce keeps resetting', async () => {
    getUnreadSummary.mockResolvedValue(makeUnreadSummary(5, 5, 5));
    await service.scheduleMessagePush(1, 5);
    jest.advanceTimersByTime(2000);
    await service.scheduleMessagePush(1, 5);
    jest.advanceTimersByTime(2000);
    await service.scheduleMessagePush(1, 5);
    jest.advanceTimersByTime(2000);
    await service.scheduleMessagePush(1, 5);
    jest.advanceTimersByTime(2000);
    await service.scheduleMessagePush(1, 5);
    expect(notify).not.toHaveBeenCalled();

    jest.advanceTimersByTime(2000);
    await Promise.resolve();
    await Promise.resolve();

    expect(notify).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenCalledWith(1, {
      conversationId: 5,
      unreadCount: 5,
      unreadTotal: 5,
      unreadConversationIds: [5],
    });
  });

  it('uses separate buckets per conversation', async () => {
    getUnreadSummary.mockResolvedValue({
      unreadTotal: 2,
      unreadConversationIds: [1, 2],
      countByConversationId: new Map([[1, 1], [2, 1]]),
    });
    await service.scheduleMessagePush(9, 1);
    await service.scheduleMessagePush(9, 2);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();

    expect(notify).toHaveBeenCalledTimes(2);
    expect(notify).toHaveBeenCalledWith(9,
      expect.objectContaining({ conversationId: 1, unreadTotal: 2 }));
    expect(notify).toHaveBeenCalledWith(9,
      expect.objectContaining({ conversationId: 2, unreadTotal: 2 }));
  });

  it('forwards senderName to notify, keeping the latest across a burst', async () => {
    getUnreadSummary.mockResolvedValue(makeUnreadSummary(10, 2, 2));
    await service.scheduleMessagePush(2, 10, 'bob');
    jest.advanceTimersByTime(1000);
    await service.scheduleMessagePush(2, 10, 'bob');
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();

    expect(notify).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenCalledWith(
      2,
      expect.objectContaining({ conversationId: 10, senderName: 'bob' }),
    );
  });

  it('omits senderName when never provided', async () => {
    getUnreadSummary.mockResolvedValue(makeUnreadSummary(10, 1, 1));
    await service.scheduleMessagePush(2, 10);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();

    expect(notify).toHaveBeenCalledTimes(1);
    expect(notify.mock.calls[0][1].senderName).toBeUndefined();
  });

  it('suppresses an immediately-repeated push with identical counts ("5 then 5")', async () => {
    getUnreadSummary.mockResolvedValue(makeUnreadSummary(10, 5, 5));

    // Burst flush #1 announces 5.
    await service.scheduleMessagePush(2, 10);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();
    expect(notify).toHaveBeenCalledTimes(1);

    // The message that raced into flush #1's summary opens bucket #2 — its
    // flush re-reads the same counts and must NOT send a second card.
    await service.scheduleMessagePush(2, 10);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();
    expect(notify).toHaveBeenCalledTimes(1);
  });

  it('does not suppress when the counts changed', async () => {
    getUnreadSummary.mockResolvedValue(makeUnreadSummary(10, 5, 5));
    await service.scheduleMessagePush(2, 10);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();
    expect(notify).toHaveBeenCalledTimes(1);

    getUnreadSummary.mockResolvedValue(makeUnreadSummary(10, 6, 6));
    await service.scheduleMessagePush(2, 10);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();
    expect(notify).toHaveBeenCalledTimes(2);
    expect(notify).toHaveBeenLastCalledWith(
      2,
      expect.objectContaining({ unreadCount: 6, unreadTotal: 6 }),
    );
  });

  it('does not suppress identical counts after the suppress window', async () => {
    getUnreadSummary.mockResolvedValue(makeUnreadSummary(10, 5, 5));
    await service.scheduleMessagePush(2, 10);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();
    expect(notify).toHaveBeenCalledTimes(1);

    // Past the 10s window (modern fake timers advance Date.now too).
    jest.advanceTimersByTime(11000);
    await service.scheduleMessagePush(2, 10);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();
    expect(notify).toHaveBeenCalledTimes(2);
  });

  it('suppresses a server-originated push for a muted conversation', async () => {
    isMuted.mockResolvedValue(true);
    await service.scheduleMessagePush(2, 10);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();

    expect(isMuted).toHaveBeenCalledWith(2, 10);
    expect(getUnreadSummary).not.toHaveBeenCalled();
    expect(notify).not.toHaveBeenCalled();
  });

  it('calls getUnreadSummaryForUser at flush time (not at schedule time)', async () => {
    getUnreadSummary.mockResolvedValue(makeUnreadSummary(10, 1, 1));
    await service.scheduleMessagePush(2, 10);
    expect(getUnreadSummary).not.toHaveBeenCalled();

    jest.advanceTimersByTime(2500);
    await Promise.resolve();
    await Promise.resolve();

    expect(getUnreadSummary).toHaveBeenCalledWith(2);
  });
});
