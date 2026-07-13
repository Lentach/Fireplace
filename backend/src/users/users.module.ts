import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MulterModule } from '@nestjs/platform-express';
import { User } from './user.entity';
import { ProfilePhoto } from './profile-photo.entity';
import { UsersService } from './users.service';
import { UsersController } from './users.controller';
import { Conversation } from '../conversations/conversation.entity';
import { Message } from '../messages/message.entity';
import { FriendRequest } from '../friends/friend-request.entity';
import { FcmTokensModule } from '../fcm-tokens/fcm-tokens.module';
import { KeyBundlesModule } from '../key-bundles/key-bundles.module';
import { MessagesModule } from '../messages/messages.module';
import { WebPushSubscriptionsModule } from '../web-push-subscriptions/web-push-subscriptions.module';
import { RefreshTokensModule } from '../auth/refresh-tokens.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      User,
      ProfilePhoto,
      Conversation,
      Message,
      FriendRequest,
    ]),
    RefreshTokensModule,
    MulterModule.register(),
    FcmTokensModule,
    WebPushSubscriptionsModule,
    KeyBundlesModule,
    MessagesModule,
  ],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
