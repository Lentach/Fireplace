// backend/src/contact/dto/subscribe-inbox.dto.ts
import { IsString, Length, MaxLength } from 'class-validator';

export class SubscribeInboxDto {
  @IsString()
  @Length(32, 128)
  key: string;

  @IsString()
  @MaxLength(2048)
  endpoint: string;

  @IsString()
  @MaxLength(512)
  p256dh: string;

  @IsString()
  @MaxLength(256)
  auth: string;
}
