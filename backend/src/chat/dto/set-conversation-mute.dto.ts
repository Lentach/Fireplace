import { IsIn, IsNumber, IsPositive } from 'class-validator';
import type { ConversationMuteDuration } from '../../conversation-notification-preferences/conversation-notification-preferences.service';

export class SetConversationMuteDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;

  @IsIn(['off', '1h', '8h', '1w', 'forever'])
  duration: ConversationMuteDuration;
}
