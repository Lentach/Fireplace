import { IsInt, IsPositive } from 'class-validator';

export class ClearChatHistoryDto {
  @IsInt()
  @IsPositive()
  conversationId: number;
}
