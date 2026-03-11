import { IsNumber, IsOptional, IsPositive } from 'class-validator';
import { Transform } from 'class-transformer';

export class UploadImageDto {
  @Transform(({ value }) => (value != null ? parseInt(value, 10) : undefined))
  @IsNumber()
  @IsPositive()
  recipientId: number;

  @Transform(({ value }) => (value != null && value !== '' ? parseInt(value, 10) : undefined))
  @IsOptional()
  @IsNumber()
  @IsPositive()
  expiresIn?: number;
}
