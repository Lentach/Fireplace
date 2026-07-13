import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConversationNotificationPreference } from './conversation-notification-preference.entity';
import { ConversationNotificationPreferencesService } from './conversation-notification-preferences.service';

@Module({
  imports: [TypeOrmModule.forFeature([ConversationNotificationPreference])],
  providers: [ConversationNotificationPreferencesService],
  exports: [ConversationNotificationPreferencesService],
})
export class ConversationNotificationPreferencesModule {}
