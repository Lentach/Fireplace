import {
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { MAX_DEVICE_ID } from '../../key-bundles/key-bundles.service';

export class UploadKeyBundleDto {
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

  @IsNumber()
  @IsPositive()
  registrationId: number;

  @IsString()
  @MinLength(1)
  identityPublicKey: string;

  @IsNumber()
  @Min(0)
  signedPreKeyId: number;

  @IsString()
  @MinLength(1)
  signedPreKeyPublic: string;

  @IsString()
  @MinLength(1)
  signedPreKeySignature: string;

  /**
   * Registration lock proof (multi-device spec §6.1). Required only when this
   * upload REPLACES a different stored identity key; absent on the normal
   * same-identity re-upload and on a first-ever upload.
   *
   * base64 XEdDSA signature by the PREVIOUS identity key over
   * newIdentityPublicKey ‖ userId ‖ nonce.
   */
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(128)
  identitySignature?: string;

  /** base64 nonce issued to this socket session, echoed back with the proof. */
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  nonce?: string;
}
