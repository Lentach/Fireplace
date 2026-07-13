import { Module } from '@nestjs/common';
import { FcmTokensModule } from '../fcm-tokens/fcm-tokens.module';
import { MessagesModule } from '../messages/messages.module';
import { PushNotificationCoalescingService } from './push-notification-coalescing.service';
import { PushNotificationsService } from './push-notifications.service';
import { ConversationNotificationPreferencesModule } from '../conversation-notification-preferences/conversation-notification-preferences.module';
import { WebPushSubscriptionsModule } from '../web-push-subscriptions/web-push-subscriptions.module';
@Module({
  imports: [
    FcmTokensModule,
    WebPushSubscriptionsModule,
    MessagesModule,
    ConversationNotificationPreferencesModule,
  ],
  providers: [PushNotificationsService, PushNotificationCoalescingService],
  exports: [PushNotificationsService, PushNotificationCoalescingService],
})
export class PushNotificationsModule {}
