import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Conversation } from './conversation.entity';
import { ConversationsService } from './conversations.service';

@Module({
  imports: [TypeOrmModule.forFeature([Conversation])],
  providers: [ConversationsService],
  exports: [ConversationsService],
})
export class ConversationsModule {}
