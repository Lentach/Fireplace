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

// Mock firebase-admin at the module level so notifyFcm can reach sendEachForMulticast.
// The same sendEachForMulticast closure is returned by every messaging() call, so a
// test can grab it via admin.messaging().sendEachForMulticast to inspect its args.
jest.mock('firebase-admin', () => {
  const sendEachForMulticast = jest.fn().mockResolvedValue({
    responses: [],
    successCount: 1,
    failureCount: 0,
  });
  return {
    apps: [],
    credential: { cert: jest.fn() },
    initializeApp: jest.fn(),
    messaging: jest.fn(() => ({ sendEachForMulticast })),
  };
});
import * as admin from 'firebase-admin';

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

  it('FCM data is a content-free wake-up: no senderName or unread counts (Google-readable channel)', async () => {
    // notifyFcm only reaches sendEachForMulticast when FCM is initialized AND the user
    // has native tokens. The shared mock returns [] by default, so wire both up here.
    interface ServiceInternals {
      fcmInitialized: boolean;
      fcmTokensService: { findTokensByUserId: jest.Mock };
    }
    const internals = service as unknown as ServiceInternals;
    internals.fcmInitialized = true;
    internals.fcmTokensService.findTokensByUserId.mockResolvedValue([
      'android-token-1',
      'ios-token-1',
    ]);

    const options: NotifyOptions = {
      conversationId: 42,
      unreadCount: 3,
      unreadTotal: 7,
      unreadConversationIds: [42, 17],
      senderName: 'Alice',
    };

    await service.notify(1, options);

    const sendEachForMulticast = admin.messaging()
      .sendEachForMulticast as jest.Mock;
    expect(sendEachForMulticast).toHaveBeenCalledTimes(1);

    const [multicastMessage] = sendEachForMulticast.mock.calls[0] as [
      { tokens: string[]; data: Record<string, string> },
    ];
    const data = multicastMessage.data;

    // The opaque routing signal survives (used for tap-routing/dedup only)...
    expect(data.type).toBe('new_message');
    expect(data.conversationId).toBe('42');
    // ...but nothing identifying who-messaged-whom or activity volume reaches Google.
    expect(data).not.toHaveProperty('senderName');
    expect(data).not.toHaveProperty('unreadCount');
    expect(data).not.toHaveProperty('unreadTotal');
    expect(data).not.toHaveProperty('unreadConversationIds');
  });

  it('Web Push sends no conv-<id> topic header (cleartext to relay), keeps TTL/urgency', async () => {
    const options: NotifyOptions = {
      conversationId: 42,
      unreadCount: 3,
      senderName: 'Alice',
    };

    await service.notify(1, options);

    expect(webPush.sendNotification).toHaveBeenCalled();
    const opts = (webPush.sendNotification as jest.Mock).mock.calls[0][2] as {
      TTL?: number;
      urgency?: string;
      topic?: string;
    };
    // A `conv-<id>` collapse-key topic would leak per-conversation cadence to the relay.
    expect(opts).not.toHaveProperty('topic');
    // Delivery hints that are safe to expose over the transport stay put.
    expect(opts.TTL).toBe(120);
    expect(opts.urgency).toBe('high');
  });
});
