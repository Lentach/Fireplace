import {
  IsInt,
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
  @IsInt()
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

  /**
   * Restore proof (amendment (lxxviii) clause 2). Present when this upload
   * RE-INSTALLS the account's stored identity from a phrase-sealed backup:
   * base64 XEdDSA signature by the STORED (= uploaded) identity key over
   * identityPublicKey ‖ userId ‖ nonce — same byte layout as
   * `identitySignature`, verified under the current IK. Ignored when the
   * uploaded identity differs from the stored one.
   */
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(128)
  restoreSignature?: string;

  /** base64 nonce issued to this socket session, echoed back with the proof. */
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  nonce?: string;
}
