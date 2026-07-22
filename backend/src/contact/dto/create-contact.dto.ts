// backend/src/contact/dto/create-contact.dto.ts
import { IsOptional, IsString, Length, MaxLength } from 'class-validator';

export class CreateContactDto {
  @IsString()
  @Length(1, 2000)
  message: string;

  @IsOptional()
  @IsString()
  @MaxLength(320)
  replyTo?: string;

  // Honeypot. Hidden field on the landing form; humans never fill it.
  // Declared here so ValidationPipe({ whitelist: true }) does not strip it —
  // the controller silently drops any submission that carries a value.
  @IsOptional()
  @IsString()
  @MaxLength(200)
  website?: string;
}
