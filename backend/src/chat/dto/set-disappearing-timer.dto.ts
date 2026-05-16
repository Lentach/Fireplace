import { IsNumber, IsOptional, Max, Min, ValidateIf } from 'class-validator';
import {
  DISAPPEARING_MAX_SECONDS,
  DISAPPEARING_MIN_SECONDS,
} from '../../messages/disappearing.constants';

export class SetDisappearingTimerDto {
  @IsNumber()
  conversationId: number;

  @IsOptional()
  @ValidateIf((o) => o.seconds != null)
  @IsNumber()
  @Min(DISAPPEARING_MIN_SECONDS)
  @Max(DISAPPEARING_MAX_SECONDS)
  seconds: number | null;
}
