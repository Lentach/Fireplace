import { IsNumber, IsPositive } from 'class-validator';

export class MessageDeliveredDto {
  @IsNumber()
  @IsPositive()
  messageId: number;
}
