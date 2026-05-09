import { Module } from '@nestjs/common';
import { FcmTokensModule } from '../fcm-tokens/fcm-tokens.module';
import { PushNotificationCoalescingService } from './push-notification-coalescing.service';
import { PushNotificationsService } from './push-notifications.service';
import { WebPushSubscriptionsModule } from '../web-push-subscriptions/web-push-subscriptions.module';

@Module({
  imports: [FcmTokensModule, WebPushSubscriptionsModule],
  providers: [PushNotificationsService, PushNotificationCoalescingService],
  exports: [PushNotificationsService, PushNotificationCoalescingService],
})
export class PushNotificationsModule {}
