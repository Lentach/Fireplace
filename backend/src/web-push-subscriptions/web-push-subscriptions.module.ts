import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { WebPushSubscription } from './web-push-subscription.entity';
import { WebPushSubscriptionsService } from './web-push-subscriptions.service';

@Module({
  imports: [TypeOrmModule.forFeature([WebPushSubscription])],
  providers: [WebPushSubscriptionsService],
  exports: [WebPushSubscriptionsService],
})
export class WebPushSubscriptionsModule {}
