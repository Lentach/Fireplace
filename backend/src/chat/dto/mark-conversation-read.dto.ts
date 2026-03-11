import { IsNumber, IsPositive } from 'class-validator';

export class MarkConversationReadDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;
}
