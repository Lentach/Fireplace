import {
  IsArray,
  IsNumber,
  IsString,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';

export class OneTimePreKeyDto {
  @IsNumber()
  @Min(0)
  keyId: number;

  @IsString()
  @MinLength(1)
  publicKey: string;
}

export class UploadOneTimePreKeysDto {
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => OneTimePreKeyDto)
  keys: OneTimePreKeyDto[];
}
