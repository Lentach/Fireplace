import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

/**
 * Starts an account-identity reset ceremony (multi-device spec §6.2).
 *
 * The optional recovery phrase shortens the delay (§6.2.1). It is bounded in
 * length so a hostile payload cannot turn the memory-hard verifier into a
 * denial-of-service lever: a 12-word phrase is far below this cap.
 */
export class ResetIdentityRequestDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  recoveryPhrase?: string;
}

/**
 * Sealed identity backup riding a phrase enrolment (amendment (lxxviii)
 * clause 1). Opaque to the server: `blob` is base64(iv12 || AES-256-GCM ct)
 * sealed under PBKDF2-HMAC-SHA256(NFKD phrase, salt, iterations). Bounds are
 * DoS caps, not crypto validation — the server cannot open the blob.
 */
export class RecoveryBackupDto {
  /** ≤ 16 KiB of base64 — the identity record is far below this. */
  @IsString()
  @MinLength(1)
  @MaxLength(16384)
  @Matches(/^[A-Za-z0-9+/]+={0,2}$/)
  blob: string;

  /** base64 PBKDF2 salt (a 16-byte salt encodes to 24 chars). */
  @IsString()
  @MinLength(16)
  @MaxLength(64)
  @Matches(/^[A-Za-z0-9+/]+={0,2}$/)
  salt: string;

  @IsInt()
  @Min(100000)
  @Max(2000000)
  iterations: number;

  /** Blob format version; 1 is the only one defined. */
  @IsInt()
  @IsIn([1])
  version: number;
}

/** Enrolls or replaces the account's recovery phrase (§6.2.1). */
export class SetRecoveryKeyDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  phrase: string;

  /**
   * The sealed identity backup, written with the verifier in one transaction
   * ((lxxviii) clause 1). Optional: an older client enrols the phrase alone
   * and the previously stored backup (if any) is left untouched.
   */
  @IsOptional()
  @ValidateNested()
  @Type(() => RecoveryBackupDto)
  backup?: RecoveryBackupDto;
}
