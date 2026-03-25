import { IsIn, IsNumber, IsOptional, IsString, MaxLength, Matches } from 'class-validator';
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
  @MaxLength(255)
  @Matches(/^[^/\\]+$/, { message: 'fileName must not contain path separators' })
  fileName?: string;
}
