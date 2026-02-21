import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { ScheduleModule } from '@nestjs/schedule';
import { AuthModule } from './auth/auth.module';
import { CloudinaryModule } from './cloudinary/cloudinary.module';
import { UsersModule } from './users/users.module';
import { ChatModule } from './chat/chat.module';
import { ConversationsModule } from './conversations/conversations.module';
import { MessagesModule } from './messages/messages.module';
import { FriendsModule } from './friends/friends.module';
import { BlockedModule } from './blocked/blocked.module';
import { FcmTokensModule } from './fcm-tokens/fcm-tokens.module';
import { KeyBundlesModule } from './key-bundles/key-bundles.module';
import { PushNotificationsModule } from './push-notifications/push-notifications.module';
import { User } from './users/user.entity';
import { Conversation } from './conversations/conversation.entity';
import { Message } from './messages/message.entity';
import { FriendRequest } from './friends/friend-request.entity';
import { BlockedUser } from './blocked/blocked-user.entity';
import { FcmToken } from './fcm-tokens/fcm-token.entity';
import { KeyBundle } from './key-bundles/key-bundle.entity';
import { OneTimePreKey } from './key-bundles/one-time-pre-key.entity';
import { validate } from './config/env.validation';

@Module({
  imports: [
    // Load and validate environment variables
    ConfigModule.forRoot({
      validate,
      isGlobal: true,
      envFilePath: ['.env.local', '.env'],
    }),
    // Schedule cron jobs for message expiration
    ScheduleModule.forRoot(),
    // Rate limiting: 100 requests per 15 minutes globally
    ThrottlerModule.forRoot([
      {
        ttl: 900000, // 15 minutes in milliseconds
        limit: 100,
      },
    ]),
    // TypeORM auto-creates tables (synchronize: true).
    // In production disable synchronize and use migrations!
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        type: 'postgres',
        host: configService.get('DB_HOST'),
        port: configService.get('DB_PORT'),
        username: configService.get('DB_USER'),
        password: configService.get('DB_PASS'),
        database: configService.get('DB_NAME'),
        entities: [User, Conversation, Message, FriendRequest, BlockedUser, FcmToken, KeyBundle, OneTimePreKey],
        synchronize: configService.get('NODE_ENV') === 'development',
      }),
    }),
    CloudinaryModule,
    AuthModule,
    UsersModule,
    ConversationsModule,
    MessagesModule,
    FriendsModule,
    BlockedModule,
    FcmTokensModule,
    KeyBundlesModule,
    PushNotificationsModule,
    ChatModule,
  ],
})
export class AppModule {}
