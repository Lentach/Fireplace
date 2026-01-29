import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Message } from './message.entity';
import { MessagesService } from './messages.service';

@Module({
  imports: [TypeOrmModule.forFeature([Message])],
  providers: [MessagesService],
  exports: [MessagesService],
})
export class MessagesModule {}
