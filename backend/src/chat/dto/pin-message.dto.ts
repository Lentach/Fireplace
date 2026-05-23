import { IsNumber, IsPositive } from 'class-validator';

export class PinMessageDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;

  @IsNumber()
  @IsPositive()
  messageId: number;
}

export class UnpinMessageDto {
  @IsNumber()
  @IsPositive()
  conversationId: number;
}
