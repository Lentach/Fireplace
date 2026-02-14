import { IsNumber, IsOptional } from 'class-validator';

export class SetDisappearingTimerDto {
  @IsNumber()
  conversationId: number;

  @IsOptional()
  @IsNumber()
  seconds: number | null;
}
