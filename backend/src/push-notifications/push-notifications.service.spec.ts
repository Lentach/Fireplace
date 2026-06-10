import { Test, TestingModule } from '@nestjs/testing';
import { PushNotificationsService, NotifyOptions } from './push-notifications.service';
import { FcmTokensService } from '../fcm-tokens/fcm-tokens.service';
import { WebPushSubscriptionsService } from '../web-push-subscriptions/web-push-subscriptions.service';

// Mock web-push at the module level
jest.mock('web-push', () => ({
  setVapidDetails: jest.fn(),
  sendNotification: jest.fn().mockResolvedValue(undefined),
}));
import * as webPush from 'web-push';

describe('PushNotificationsService payload', () => {
  let service: PushNotificationsService;

  beforeEach(async () => {
    jest.clearAllMocks();
    process.env.WEB_PUSH_VAPID_PUBLIC_KEY = 'test-pub-key';
    process.env.WEB_PUSH_VAPID_PRIVATE_KEY = 'test-priv-key';

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PushNotificationsService,
        {
          provide: FcmTokensService,
          useValue: { findTokensByUserId: jest.fn().mockResolvedValue([]) },
        },
        {
          provide: WebPushSubscriptionsService,
          useValue: {
            findByUserId: jest.fn().mockResolvedValue([
              { endpoint: 'https://example.com/push/1', p256dh: 'abc', auth: 'def' },
            ]),
            removeByEndpoints: jest.fn().mockResolvedValue(undefined),
          },
        },
      ],
    }).compile();

    service = module.get(PushNotificationsService);
    // Mark as initialized so actual sends run
    (service as any).webPushInitialized = true;
  });

  afterEach(() => {
    delete process.env.WEB_PUSH_VAPID_PUBLIC_KEY;
    delete process.env.WEB_PUSH_VAPID_PRIVATE_KEY;
  });

  it('includes conversationId, unreadCount, unreadTotal, unreadConversationIds in Web Push payload', async () => {
    const options: NotifyOptions = {
      conversationId: 42,
      unreadCount: 3,
      unreadTotal: 7,
      unreadConversationIds: [42, 17],
    };

    await service.notify(1, options);

    expect(webPush.sendNotification).toHaveBeenCalled();
    const rawPayload = (webPush.sendNotification as jest.Mock).mock.calls[0][1] as string;
    const payload = JSON.parse(rawPayload);
    expect(payload.conversationId).toBe(42);
    expect(payload.unreadCount).toBe(3);
    expect(payload.unreadTotal).toBe(7);
    expect(payload.unreadConversationIds).toEqual([42, 17]);
  });

  it('omits optional fields when not provided', async () => {
    const options: NotifyOptions = { conversationId: 99 };

    await service.notify(1, options);

    const rawPayload = (webPush.sendNotification as jest.Mock).mock.calls[0][1] as string;
    const payload = JSON.parse(rawPayload);
    expect(payload.conversationId).toBe(99);
    expect(payload.unreadCount).toBeUndefined();
    expect(payload.unreadTotal).toBeUndefined();
    expect(payload.unreadConversationIds).toBeUndefined();
  });
});
