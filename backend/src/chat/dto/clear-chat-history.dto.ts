import { IsNumber } from 'class-validator';

export class ClearChatHistoryDto {
  @IsNumber()
  conversationId: number;
}
