import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BlockedUser } from './blocked-user.entity';
import { BlockedService } from './blocked.service';
import { FriendsModule } from '../friends/friends.module';
import { ConversationsModule } from '../conversations/conversations.module';
import { MessagesModule } from '../messages/messages.module';
import { MediaModule } from '../media/media.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([BlockedUser]),
    FriendsModule,
    ConversationsModule,
    MessagesModule,
    MediaModule,
  ],
  providers: [BlockedService],
  exports: [BlockedService],
})
export class BlockedModule {}
