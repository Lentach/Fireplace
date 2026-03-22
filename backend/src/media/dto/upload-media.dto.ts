import { IsIn, IsNumber, IsOptional, IsString } from 'class-validator';
import { Type } from 'class-transformer';

export class UploadMediaDto {
  @IsIn(['image', 'voice', 'gif', 'file', 'avatar'])
  mediaType: 'image' | 'voice' | 'gif' | 'file' | 'avatar';

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  duration?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  expiresIn?: number;

  @IsOptional()
  @IsString()
  fileName?: string;
}
