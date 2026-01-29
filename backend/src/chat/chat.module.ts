import { Module } from '@nestjs/common';
import { ChatGateway } from './chat.gateway';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { ConversationsModule } from '../conversations/conversations.module';
import { MessagesModule } from '../messages/messages.module';

@Module({
  imports: [AuthModule, UsersModule, ConversationsModule, MessagesModule],
  providers: [ChatGateway],
})
export class ChatModule {}
