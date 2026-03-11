import { IsNumber, IsPositive } from 'class-validator';

export class TypingDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;

  @IsNumber()
  @IsPositive()
  conversationId: number;
}
