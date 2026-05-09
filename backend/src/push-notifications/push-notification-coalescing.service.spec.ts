import { Test, TestingModule } from '@nestjs/testing';
import { PushNotificationCoalescingService } from './push-notification-coalescing.service';
import { PushNotificationsService } from './push-notifications.service';

describe('PushNotificationCoalescingService', () => {
  let service: PushNotificationCoalescingService;
  let notify: jest.Mock;

  beforeEach(async () => {
    jest.useFakeTimers();
    notify = jest.fn().mockResolvedValue(undefined);
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PushNotificationCoalescingService,
        { provide: PushNotificationsService, useValue: { notify } },
      ],
    }).compile();

    service = module.get(PushNotificationCoalescingService);
  });

  afterEach(() => {
    service.onModuleDestroy();
    jest.useRealTimers();
  });

  it('aggregates bursts into one notify after debounce', async () => {
    await service.scheduleMessagePush(2, 10);
    await service.scheduleMessagePush(2, 10);
    await service.scheduleMessagePush(2, 10);
    expect(notify).not.toHaveBeenCalled();

    jest.advanceTimersByTime(2500);
    await Promise.resolve();

    expect(notify).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenCalledWith(2, {
      conversationId: 10,
      messageCount: 3,
    });
  });

  it('flushes by max wait when debounce keeps resetting', async () => {
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

    expect(notify).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenCalledWith(1, {
      conversationId: 5,
      messageCount: 5,
    });
  });

  it('uses separate buckets per conversation', async () => {
    await service.scheduleMessagePush(9, 1);
    await service.scheduleMessagePush(9, 2);
    jest.advanceTimersByTime(2500);
    await Promise.resolve();

    expect(notify).toHaveBeenCalledTimes(2);
    expect(notify).toHaveBeenCalledWith(9, {
      conversationId: 1,
      messageCount: 1,
    });
    expect(notify).toHaveBeenCalledWith(9, {
      conversationId: 2,
      messageCount: 1,
    });
  });
});
