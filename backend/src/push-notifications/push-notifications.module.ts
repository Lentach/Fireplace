import { Module } from '@nestjs/common';
import { FcmTokensModule } from '../fcm-tokens/fcm-tokens.module';
import { PushNotificationsService } from './push-notifications.service';
import { WebPushSubscriptionsModule } from '../web-push-subscriptions/web-push-subscriptions.module';

@Module({
  imports: [FcmTokensModule, WebPushSubscriptionsModule],
  providers: [PushNotificationsService],
  exports: [PushNotificationsService],
})
export class PushNotificationsModule {}
