import { IsNumber, IsPositive } from 'class-validator';

export class SendPingDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;
}
