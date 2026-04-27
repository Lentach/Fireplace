import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Message } from './message.entity';
import { MessagesService } from './messages.service';
import { MessageCleanupService } from './message-cleanup.service';
import { MessagesController } from './messages.controller';
import { LinkPreviewModule } from '../chat/services/link-preview.module';
import { MediaModule } from '../media/media.module';

@Module({
  imports: [TypeOrmModule.forFeature([Message]), LinkPreviewModule, MediaModule],
  controllers: [MessagesController],
  providers: [MessagesService, MessageCleanupService],
  exports: [MessagesService],
})
export class MessagesModule {}
