import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MulterModule } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { Message } from './message.entity';
import { MessagesService } from './messages.service';
import { MessageCleanupService } from './message-cleanup.service';
import { MessagesController } from './messages.controller';
import { CloudinaryModule } from '../cloudinary/cloudinary.module';
import { ConversationsModule } from '../conversations/conversations.module';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Message]),
    MulterModule.register({
      storage: memoryStorage(),
    }),
    CloudinaryModule,
    ConversationsModule,
    UsersModule,
  ],
  controllers: [MessagesController],
  providers: [MessagesService, MessageCleanupService],
  exports: [MessagesService],
})
export class MessagesModule {}
