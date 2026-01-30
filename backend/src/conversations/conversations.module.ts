import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Conversation } from './conversation.entity';
import { ConversationsService } from './conversations.service';
import { Message } from '../messages/message.entity';

@Module({
  imports: [TypeOrmModule.forFeature([Conversation, Message])],
  providers: [ConversationsService],
  exports: [ConversationsService],
})
export class ConversationsModule {}
