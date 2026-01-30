import { Module } from '@nestjs/common';
import { ChatGateway } from './chat.gateway';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { ConversationsModule } from '../conversations/conversations.module';
import { MessagesModule } from '../messages/messages.module';
import { FriendsModule } from '../friends/friends.module';

@Module({
  imports: [AuthModule, UsersModule, ConversationsModule, MessagesModule, FriendsModule],
  providers: [ChatGateway],
})
export class ChatModule {}
