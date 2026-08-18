import {
  IsArray,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { MAX_DEVICE_ID } from '../../key-bundles/key-bundles.service';
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
  /**
   * Which device of the caller's account this is about (Phase 1, spec §4).
   * Absent means device 1: a client that has never heard of devices is the
   * account's original one (§8 rollout — server first, clients later).
   */
  @IsOptional()
  @IsNumber()
  @IsPositive()
  @Max(MAX_DEVICE_ID)
  deviceId?: number;

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
