import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { ChatModule } from './chat/chat.module';
import { ConversationsModule } from './conversations/conversations.module';
import { MessagesModule } from './messages/messages.module';
import { FriendsModule } from './friends/friends.module';
import { User } from './users/user.entity';
import { Conversation } from './conversations/conversation.entity';
import { Message } from './messages/message.entity';
import { FriendRequest } from './friends/friend-request.entity';

@Module({
  imports: [
    // TypeORM auto-creates tables (synchronize: true).
    // In production disable synchronize and use migrations!
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      username: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASS || 'postgres',
      database: process.env.DB_NAME || 'chatdb',
      entities: [User, Conversation, Message, FriendRequest],
      synchronize: true, // Development only!
    }),
    AuthModule,
    UsersModule,
    ConversationsModule,
    MessagesModule,
    FriendsModule,
    ChatModule,
  ],
})
export class AppModule {}
