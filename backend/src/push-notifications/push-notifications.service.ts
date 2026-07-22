import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as admin from 'firebase-admin';
import { FcmTokensService } from '../fcm-tokens/fcm-tokens.service';
import * as webPush from 'web-push';
import { WebPushSubscriptionsService } from '../web-push-subscriptions/web-push-subscriptions.service';

export interface NotifyOptions {
  conversationId: number;            // required — always present (coalescing bucket key)
  unreadCount?: number;              // cumulative unread in this conversation
  unreadTotal?: number;              // user's total unread across all conversations
  unreadConversationIds?: number[];  // conv IDs with unread > 0
  senderName?: string;               // sender display name (metadata-only; approved for notification title)
}

@Injectable()
export class PushNotificationsService implements OnModuleInit {
  private readonly logger = new Logger(PushNotificationsService.name);
  private fcmInitialized = false;
  private webPushInitialized = false;

  constructor(
    private readonly fcmTokensService: FcmTokensService,
    private readonly webPushSubscriptionsService: WebPushSubscriptionsService,
  ) {}

  onModuleInit() {
    this.initializeFcm();
    this.initializeWebPush();
  }

  private initializeFcm() {
    const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (!serviceAccountJson) {
      this.logger.warn('FIREBASE_SERVICE_ACCOUNT not set — FCM push disabled');
      return;
    }

    if (admin.apps.length === 0) {
      try {
        admin.initializeApp({
          credential: admin.credential.cert(JSON.parse(serviceAccountJson)),
        });
        this.fcmInitialized = true;
        this.logger.log('Firebase Admin initialized');
      } catch (err) {
        this.logger.error('Firebase Admin init failed', err);
      }
    } else {
      this.fcmInitialized = true;
    }
  }

  private initializeWebPush() {
    const publicKey = process.env.WEB_PUSH_VAPID_PUBLIC_KEY;
    const privateKey = process.env.WEB_PUSH_VAPID_PRIVATE_KEY;
    const subject =
      process.env.WEB_PUSH_VAPID_SUBJECT ?? 'mailto:fireplace@example.com';

    if (!publicKey || !privateKey) {
      this.logger.warn(
        'WEB_PUSH_VAPID_PUBLIC_KEY/WEB_PUSH_VAPID_PRIVATE_KEY not set — Web Push disabled',
      );
      return;
    }

    try {
      webPush.setVapidDetails(subject, publicKey, privateKey);
      this.webPushInitialized = true;
      this.logger.log('Web Push VAPID initialized');
    } catch (err) {
      this.logger.error('Web Push VAPID init failed', err);
    }
  }

  async notify(userId: number, options: NotifyOptions): Promise<void> {
    await Promise.all([
      this.notifyFcm(userId, options),
      this.notifyWebPush(userId, options),
    ]);
  }

  private async notifyFcm(userId: number, options: NotifyOptions): Promise<void> {
    if (!this.fcmInitialized) return;

    // Web clients are moving to standards-based Web Push.
    const tokens = await this.fcmTokensService.findTokensByUserId(userId, [
      'android',
      'ios',
    ]);
    if (!tokens.length) return;

    // Content-free wake-up (Signal/Wire model): the FCM `data` map transits Google
    // READABLE, so it carries ONLY the event type + conversationId (an opaque int used
    // for notification tap-routing/dedup). It intentionally omits senderName and unread
    // counts — those would leak who-messaged-whom and activity volume to Google. The app
    // wakes on this signal and fetches real state over its own authenticated socket.
    const data: Record<string, string> = {
      type: 'new_message',
      conversationId: String(options.conversationId),
    };

    try {
      const result = await admin.messaging().sendEachForMulticast({
        tokens,
        data, // metadata only — no message body
        android: { priority: 'high' },
        apns: { payload: { aps: { contentAvailable: true } } }, // silent push iOS
      });

      // Cleanup stale tokens (registration expired)
      const staleTokens: string[] = [];
      result.responses.forEach((r, i) => {
        if (
          !r.success &&
          r.error?.code === 'messaging/registration-token-not-registered'
        ) {
          staleTokens.push(tokens[i]);
        }
      });
      if (staleTokens.length) {
        await this.fcmTokensService.removeByTokens(staleTokens);
        this.logger.debug(
          `FCM cleanup removed ${staleTokens.length} stale tokens for userId=${userId}`,
        );
      }
      this.logger.debug(
        `FCM push attempted for userId=${userId}, tokens=${tokens.length}, success=${result.successCount}, failure=${result.failureCount}`,
      );
    } catch (err) {
      this.logger.error(`Failed to send push to userId=${userId}`, err);
    }
  }

  private async notifyWebPush(
    userId: number,
    options: NotifyOptions,
  ): Promise<void> {
    const body: Record<string, unknown> = {
      type: 'new_message',
      conversationId: options.conversationId,
    };
    if (options.unreadCount != null) {
      body.unreadCount = options.unreadCount;
    }
    if (options.unreadTotal != null) {
      body.unreadTotal = options.unreadTotal;
    }
    if (options.unreadConversationIds != null) {
      body.unreadConversationIds = options.unreadConversationIds;
    }
    if (options.senderName != null) {
      body.senderName = options.senderName;
    }
    await this.sendWebPushToUser(userId, body);
  }

  private async sendWebPushToUser(
    userId: number,
    body: Record<string, unknown>,
  ): Promise<void> {
    if (!this.webPushInitialized) return;

    const subscriptions = await this.webPushSubscriptionsService.findByUserId(
      userId,
    );
    if (!subscriptions.length) return;

    // Deliberately NO `topic` (RFC 8030 collapse key): a `conv-<id>` topic is sent as a
    // CLEARTEXT header to the push relay (Mozilla/Apple/Google) and would leak per-
    // conversation activity + cadence. The payload body below is E2E-encrypted to the
    // browser, so senderName/counts inside it stay private; server-side coalescing and
    // client-side notification tags already de-dupe bursts without a relay collapse key.
    const payload = JSON.stringify(body);

    const staleEndpoints: string[] = [];
    for (const subscription of subscriptions) {
      try {
        await webPush.sendNotification(
          {
            endpoint: subscription.endpoint,
            keys: {
              p256dh: subscription.p256dh,
              auth: subscription.auth,
            },
          },
          payload,
          {
            TTL: 120,
            urgency: 'high',
          },
        );
      } catch (err: any) {
        const statusCode = Number(err?.statusCode);
        // 404/410 = gone; 400 often = VAPID/crypto mismatch or permanently invalid sub.
        if (statusCode === 400 || statusCode === 404 || statusCode === 410) {
          staleEndpoints.push(subscription.endpoint);
          if (statusCode === 400) {
            this.logger.warn(
              `Web Push subscription rejected (400) for userId=${userId} — removing; client must re-enable push in Settings`,
            );
          }
          continue;
        }
        this.logger.warn(
          `Web Push delivery failed for userId=${userId}, status=${statusCode || 'unknown'}`,
        );
      }
    }

    if (staleEndpoints.length) {
      await this.webPushSubscriptionsService.removeByEndpoints(staleEndpoints);
      this.logger.debug(
        `Web Push cleanup removed ${staleEndpoints.length} stale subscriptions for userId=${userId}`,
      );
    }
    this.logger.debug(
      `Web Push attempted for userId=${userId}, subscriptions=${subscriptions.length}, stale=${staleEndpoints.length}`,
    );
  }
}
