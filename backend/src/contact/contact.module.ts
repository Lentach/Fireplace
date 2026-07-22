// backend/src/contact/contact.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ContactMessage } from './contact-message.entity';
import { ContactPushSubscription } from './contact-push-subscription.entity';
import { ContactService } from './contact.service';
import { ContactController } from './contact.controller';
import { PushNotificationsModule } from '../push-notifications/push-notifications.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([ContactMessage, ContactPushSubscription]),
    PushNotificationsModule,
  ],
  providers: [ContactService],
  controllers: [ContactController],
})
export class ContactModule {}
