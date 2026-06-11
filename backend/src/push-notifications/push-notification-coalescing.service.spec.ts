import { Test, TestingModule } from '@nestjs/testing';
import { PushNotificationCoalescingService } from './push-notification-coalescing.service';
import { PushNotificationsService } from './push-notifications.service';
import { MessagesService } from '../messages/messages.service';

describe('PushNotificationCoalescingService', () => {
  let service: PushNotificationCoalescingService;
  let notify: jest.Mock;
  let getUnreadSummary: jest.Mock;

  const makeUnreadSummary = (convId: number, convCount: number, total: number) => ({
    unreadTotal: total,
    unreadConversationIds: [convId],
    countByConversationId: new Map([[convId, convCount]]),
  });

  beforeEach(async () => {
    jest.useFakeTimers();
    notify = jest.fn().mockResolvedValue(undefined);
    getUnreadSummary = jest.fn().mockResolvedValue(makeUnreadSummary(10, 3, 3));

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PushNotificationCoalescingService,
        { provide: PushNotificationsService, useValue: { notify } },
        { provide: MessagesService, useValue: { getUnreadSummaryForUser: getUnreadSummary } },
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
