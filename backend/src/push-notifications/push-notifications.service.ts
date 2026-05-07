import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as admin from 'firebase-admin';
import { FcmTokensService } from '../fcm-tokens/fcm-tokens.service';
import * as webPush from 'web-push';
import { WebPushSubscriptionsService } from '../web-push-subscriptions/web-push-subscriptions.service';

interface NotifyOptions {
  conversationId?: number;
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

  async notify(userId: number, options: NotifyOptions = {}): Promise<void> {
    await Promise.all([
      this.notifyFcm(userId),
      this.notifyWebPush(userId, options),
    ]);
  }

  private async notifyFcm(userId: number): Promise<void> {
    if (!this.fcmInitialized) return;

    // Web clients are moving to standards-based Web Push.
    const tokens = await this.fcmTokensService.findTokensByUserId(userId, [
      'android',
      'ios',
    ]);
    if (!tokens.length) return;

    try {
      const result = await admin.messaging().sendEachForMulticast({
        tokens,
        data: { type: 'new_message' }, // empty payload — privacy like Signal
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
        this.logger.log(
          `FCM cleanup removed ${staleTokens.length} stale tokens for userId=${userId}`,
        );
      }
      this.logger.log(
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
    if (!this.webPushInitialized) return;

    const subscriptions = await this.webPushSubscriptionsService.findByUserId(
      userId,
    );
    if (!subscriptions.length) return;

    const payload = JSON.stringify({
      type: 'new_message',
      conversationId: options.conversationId ?? null,
    });
    const topic = options.conversationId
      ? `conv-${options.conversationId}`.slice(0, 32)
      : 'new-message';

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
            topic,
          },
        );
      } catch (err: any) {
        const statusCode = Number(err?.statusCode);
        if (statusCode === 404 || statusCode === 410) {
          staleEndpoints.push(subscription.endpoint);
          continue;
        }
        this.logger.warn(
          `Web Push delivery failed for userId=${userId}, endpoint=${subscription.endpoint}, status=${statusCode || 'unknown'}`,
        );
      }
    }

    if (staleEndpoints.length) {
      await this.webPushSubscriptionsService.removeByEndpoints(staleEndpoints);
      this.logger.log(
        `Web Push cleanup removed ${staleEndpoints.length} stale subscriptions for userId=${userId}`,
      );
    }
    this.logger.log(
      `Web Push attempted for userId=${userId}, subscriptions=${subscriptions.length}, stale=${staleEndpoints.length}`,
    );
  }
}
