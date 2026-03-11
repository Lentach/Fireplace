import { Module } from '@nestjs/common';
import { FriendsModule } from '../friends/friends.module';
import { BlockedModule } from '../blocked/blocked.module';
import { ChatValidationService } from './services/chat-validation.service';

@Module({
  imports: [FriendsModule, BlockedModule],
  providers: [ChatValidationService],
  exports: [ChatValidationService],
})
export class ChatValidationModule {}
