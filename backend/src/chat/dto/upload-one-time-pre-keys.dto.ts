import {
  IsArray,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
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

  /**
   * Optional identity epoch tag (base64 public identity key) these OTPs were
   * generated under. New clients send it so the server binds each OTP to the
   * correct epoch regardless of upload ordering; old clients omit it and the
   * server back-fills from the current bundle.
   */
  @IsOptional()
  @IsString()
  @MinLength(1)
  // A Curve25519 identity public key is ~44 base64 chars; 255 is generous
  // headroom while bounding the per-OTP write surface (defense in depth).
  @MaxLength(255)
  identityPublicKey?: string;
}
