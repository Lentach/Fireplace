import { IsIn, IsNumber, IsOptional, IsPositive } from 'class-validator';
import { Transform } from 'class-transformer';

export class UploadMediaDto {
  @Transform(({ value }) => typeof value === 'string' ? value : String(value))
  @IsIn(['image', 'voice'])
  type: 'image' | 'voice';

  @Transform(({ value }) => (value != null && value !== '' ? parseInt(value, 10) : undefined))
  @IsOptional()
  @IsNumber()
  @IsPositive()
  duration?: number;

  @Transform(({ value }) => (value != null && value !== '' ? parseInt(value, 10) : undefined))
  @IsOptional()
  @IsNumber()
  @IsPositive()
  expiresIn?: number;
}
