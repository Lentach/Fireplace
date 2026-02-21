import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MulterModule } from '@nestjs/platform-express';
import { User } from './user.entity';
import { UsersService } from './users.service';
import { UsersController } from './users.controller';
import { Conversation } from '../conversations/conversation.entity';
import { Message } from '../messages/message.entity';
import { FriendRequest } from '../friends/friend-request.entity';
import { FcmTokensModule } from '../fcm-tokens/fcm-tokens.module';
import { KeyBundlesModule } from '../key-bundles/key-bundles.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([User, Conversation, Message, FriendRequest]),
    MulterModule.register(),
    FcmTokensModule,
    KeyBundlesModule,
  ],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
