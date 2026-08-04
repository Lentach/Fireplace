import { Test, TestingModule } from '@nestjs/testing';
import { Logger } from '@nestjs/common';
import {
  PushNotificationsService,
  NotifyOptions,
} from './push-notifications.service';
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
          useValue: {
            findTokensByUserId: jest.fn().mockResolvedValue([]),
            removeByTokens: jest.fn().mockResolvedValue(undefined),
          },
        },
        {
          provide: WebPushSubscriptionsService,
          useValue: {
            findByUserId: jest
              .fn()
              .mockResolvedValue([
                {
                  endpoint: 'https://example.com/push/1',
                  p256dh: 'abc',
                  auth: 'def',
                },
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
    const rawPayload = (webPush.sendNotification as jest.Mock).mock
      .calls[0][1] as string;
    const payload = JSON.parse(rawPayload);
    expect(payload.conversationId).toBe(42);
    expect(payload.unreadCount).toBe(3);
    expect(payload.unreadTotal).toBe(7);
    expect(payload.unreadConversationIds).toEqual([42, 17]);
  });

  it('omits optional fields when not provided', async () => {
    const options: NotifyOptions = { conversationId: 99 };

    await service.notify(1, options);

    const rawPayload = (webPush.sendNotification as jest.Mock).mock
      .calls[0][1] as string;
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
    // Approved-metadata inclusion contract: senderName IS carried in the (E2E-encrypted)
    // web-push body, unlike the FCM channel which strips it.
    const rawPayload = (webPush.sendNotification as jest.Mock).mock
      .calls[0][1] as string;
    const payload = JSON.parse(rawPayload);
    expect(payload.senderName).toBe('Alice');
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

  it('prunes a dead Web Push subscription when send rejects with 410 Gone', async () => {
    interface WebPushInternals {
      webPushSubscriptionsService: { removeByEndpoints: jest.Mock };
    }
    (webPush.sendNotification as jest.Mock).mockRejectedValueOnce({
      statusCode: 410,
    });
    const { removeByEndpoints } = (service as unknown as WebPushInternals)
      .webPushSubscriptionsService;

    await service.notify(1, { conversationId: 42 });

    expect(removeByEndpoints).toHaveBeenCalledWith([
      'https://example.com/push/1',
    ]);
  });

  it('does NOT prune a Web Push subscription on a transient 500', async () => {
    interface WebPushInternals {
      webPushSubscriptionsService: { removeByEndpoints: jest.Mock };
    }
    (webPush.sendNotification as jest.Mock).mockRejectedValueOnce({
      statusCode: 500,
    });
    const { removeByEndpoints } = (service as unknown as WebPushInternals)
      .webPushSubscriptionsService;

    await service.notify(1, { conversationId: 42 });

    expect(removeByEndpoints).not.toHaveBeenCalled();
  });

  it('prunes an unregistered FCM token reported by sendEachForMulticast', async () => {
    interface ServiceInternals {
      fcmInitialized: boolean;
      fcmTokensService: {
        findTokensByUserId: jest.Mock;
        removeByTokens: jest.Mock;
      };
    }
    const internals = service as unknown as ServiceInternals;
    internals.fcmInitialized = true;
    internals.fcmTokensService.findTokensByUserId.mockResolvedValue([
      'good-token',
      'dead-token',
    ]);

    (admin.messaging().sendEachForMulticast as jest.Mock).mockResolvedValueOnce(
      {
        responses: [
          { success: true },
          {
            success: false,
            error: { code: 'messaging/registration-token-not-registered' },
          },
        ],
        successCount: 1,
        failureCount: 1,
      },
    );

    await service.notify(1, { conversationId: 42 });

    expect(internals.fcmTokensService.removeByTokens).toHaveBeenCalledWith([
      'dead-token',
    ]);
  });

  it('KEEPS the Web Push subscription when the relay rejects with 400 (payload/VAPID fault)', async () => {
    interface WebPushInternals {
      webPushSubscriptionsService: { removeByEndpoints: jest.Mock };
    }
    // A 400 is a payload/VAPID/library fault the relay returns for EVERY send, not a
    // per-subscription verdict. Pruning on it would wipe every live row within a few cycles
    // (BE-500) — recovery then needs every user to re-enable push manually.
    (webPush.sendNotification as jest.Mock).mockRejectedValueOnce({
      statusCode: 400,
    });
    const { removeByEndpoints } = (service as unknown as WebPushInternals)
      .webPushSubscriptionsService;

    await service.notify(1, { conversationId: 42 });

    expect(removeByEndpoints).not.toHaveBeenCalled();
  });

  it('prunes a dead Web Push subscription when send rejects with 404 (Not Found)', async () => {
    interface WebPushInternals {
      webPushSubscriptionsService: { removeByEndpoints: jest.Mock };
    }
    (webPush.sendNotification as jest.Mock).mockRejectedValueOnce({
      statusCode: 404,
    });
    const { removeByEndpoints } = (service as unknown as WebPushInternals)
      .webPushSubscriptionsService;

    await service.notify(1, { conversationId: 42 });

    expect(removeByEndpoints).toHaveBeenCalledWith([
      'https://example.com/push/1',
    ]);
  });

  it('does NOT prune a Web Push subscription when the send times out', async () => {
    jest.useFakeTimers();
    try {
      interface WebPushInternals {
        webPushSubscriptionsService: { removeByEndpoints: jest.Mock };
      }
      // A half-open TCP connection: the send never settles. The explicit timeout must fire
      // and be treated as transient — NEVER as "subscription gone" (that is BE-500 by
      // another route: a relay stall would become permanent mass unsubscription).
      (webPush.sendNotification as jest.Mock).mockImplementationOnce(
        () => new Promise(() => {}),
      );
      const { removeByEndpoints } = (service as unknown as WebPushInternals)
        .webPushSubscriptionsService;

      const notifyPromise = service.notify(1, { conversationId: 42 });
      await jest.advanceTimersByTimeAsync(10000);
      await notifyPromise;

      expect(removeByEndpoints).not.toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
    }
  });

  it('one hung endpoint does not starve the remaining subscriptions', async () => {
    jest.useFakeTimers();
    try {
      interface WebPushInternals {
        webPushSubscriptionsService: {
          findByUserId: jest.Mock;
          removeByEndpoints: jest.Mock;
        };
      }
      const internals = (service as unknown as WebPushInternals)
        .webPushSubscriptionsService;
      internals.findByUserId.mockResolvedValue([
        {
          endpoint: 'https://example.com/push/hung',
          p256dh: 'abc',
          auth: 'def',
        },
        {
          endpoint: 'https://example.com/push/live',
          p256dh: 'ghi',
          auth: 'jkl',
        },
      ]);
      // First subscription hangs forever; the second must still be attempted and succeed.
      (webPush.sendNotification as jest.Mock)
        .mockImplementationOnce(() => new Promise(() => {}))
        .mockResolvedValueOnce(undefined);

      const notifyPromise = service.notify(1, { conversationId: 42 });
      // Flush the async subscription lookup so the sends dispatch, but stay BEFORE the
      // hung endpoint's timeout: both must already be attempted, proving the second is
      // not serialized behind the first.
      await jest.advanceTimersByTimeAsync(0);
      expect(webPush.sendNotification).toHaveBeenCalledTimes(2);

      await jest.advanceTimersByTimeAsync(10000);
      await notifyPromise;

      // The hung endpoint timed out (transient) so nothing is pruned.
      expect(internals.removeByEndpoints).not.toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
    }
  });

  it('never logs the recipient userId above debug on a delivery failure', async () => {
    const warnSpy = jest.spyOn(Logger.prototype, 'warn');
    const errorSpy = jest.spyOn(Logger.prototype, 'error');
    // A transient 5xx is an operational failure; the prod logger keeps error/warn/log, so
    // any recipient identifier at those levels would breach the metadata-privacy contract.
    (webPush.sendNotification as jest.Mock).mockRejectedValueOnce({
      statusCode: 500,
    });

    await service.notify(1, { conversationId: 42 });

    const leaked = [...warnSpy.mock.calls, ...errorSpy.mock.calls].some(
      (args) =>
        args.some((a) => typeof a === 'string' && a.includes('userId=')),
    );
    expect(leaked).toBe(false);
    warnSpy.mockRestore();
    errorSpy.mockRestore();
  });
});
