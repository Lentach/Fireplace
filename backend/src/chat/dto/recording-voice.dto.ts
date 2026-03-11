import { IsBoolean, IsNumber, IsPositive } from 'class-validator';
import { Transform } from 'class-transformer';

export class RecordingVoiceDto {
  @IsNumber()
  @IsPositive()
  recipientId: number;

  @IsNumber()
  @IsPositive()
  conversationId: number;

  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  isRecording: boolean;
}
