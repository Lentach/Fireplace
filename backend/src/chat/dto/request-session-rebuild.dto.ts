import { IsNumber, IsPositive } from 'class-validator';

export class RequestSessionRebuildDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;
}
